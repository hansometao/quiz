/**
 * BackupService.ets
 * 备份 & 还原服务
 *   - exportBackup()   ：将全量数据打包为 JSON，写入沙盒 files/ 目录并弹出分享
 *   - importBackup()   ：读取用户选择的 .quizbackup 文件，解析后还原至 DB
 *   - exportMistakes() ：将错题导出为 CSV（xlsx 依赖原生 zlib，改为 CSV 更可靠）
 */

import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import common from '@ohos.app.ability.common';
import { DatabaseService } from './DatabaseService';
import { QuestionBank, Question, PracticeSession, AnswerRecord, MistakeItem } from '../model/Models';

/** 备份文件的顶层数据结构 */
interface BackupData {
  version: number;
  exportTime: string;
  banks: QuestionBank[];
  questions: Question[];
  sessions: PracticeSession[];
  answerRecords: AnswerRecord[];
  mistakes: MistakeItem[];
}

export class BackupService {
  private static instance: BackupService;
  private db: DatabaseService = DatabaseService.getInstance();

  static getInstance(): BackupService {
    if (!BackupService.instance) {
      BackupService.instance = new BackupService();
    }
    return BackupService.instance;
  }

  // ─────────────────── 导出备份 ───────────────────

  /**
   * 将全量数据序列化为 JSON，保存到沙盒，返回文件路径
   */
  async exportBackup(ctx: common.UIAbilityContext): Promise<string> {
    const banks    = await this.db.getAllBanks();
    const sessions = await this.db.getAllSessions();
    const mistakes = await this.db.getAllMistakes();

    // 逐题库拉取题目
    const questions: Question[] = [];
    for (const b of banks) {
      // 使用可选链保护，bank.id 理论上必有，但类型标注为可选
      if (b.id !== undefined) {
        const qs = await this.db.getQuestions(b.id, { limit: 99999, offset: 0 });
        questions.push(...qs);
      }
    }

    // 逐 Session 拉取答题记录
    const answerRecords: AnswerRecord[] = [];
    for (const s of sessions) {
      if (s.id !== undefined) {
        const recs = await this.db.getAnswerRecords(s.id);
        answerRecords.push(...recs);
      }
    }

    const data: BackupData = {
      version:     1,
      exportTime:  new Date().toISOString(),
      banks,
      questions,
      sessions,
      answerRecords,
      mistakes,
    };

    const json     = JSON.stringify(data);
    const fileName = 'quiz_backup_' + this.dateTag() + '.quizbackup';
    const filePath = ctx.filesDir + '/' + fileName;

    const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, json);
    fs.closeSync(file);

    return filePath;
  }

  // ─────────────────── 导入还原 ───────────────────

  /**
   * 弹出文件选择器，让用户选取 .quizbackup 文件，然后还原数据
   * 返回 { success, message }
   */
  async importBackup(ctx: common.UIAbilityContext): Promise<{ success: boolean; message: string }> {
    try {
      // 打开文件选择器
      const docPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await docPicker.select({
        maxSelectNumber: 1,
        defaultFilePathUri: 'file://docs/storage/Users/currentUser/Documents',
      });

      if (!uris || uris.length === 0) {
        return { success: false, message: '未选择文件' };
      }

      const uri = uris[0];
      // 将 uri 拷贝到沙盒后读取（避免权限失效）
      const tmpPath = ctx.cacheDir + '/import_tmp.quizbackup';
      fs.copyFileSync(uri, tmpPath);

      const file = fs.openSync(tmpPath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(tmpPath);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      const json = this.arrayBufferToString(buf);
      const data: BackupData = JSON.parse(json) as BackupData;

      if (!data.version || !data.banks) {
        return { success: false, message: '文件格式不正确' };
      }

      // 执行还原（追加模式，不删除现有数据；如需覆盖可先调用 db.clearAll）
      await this.db.restoreFromBackup(data.banks, data.questions, data.sessions, data.answerRecords, data.mistakes);

      // 清理临时文件
      fs.unlinkSync(tmpPath);

      return {
        success: true,
        message: `还原成功：${data.banks.length} 个题库，${data.questions.length} 道题目`
      };
    } catch (e) {
      const err = e as Error;
      return { success: false, message: '还原失败：' + err.message };
    }
  }

  // ─────────────────── 导出错题 CSV ───────────────────

  /**
   * 将全部错题导出为 CSV，保存到沙盒，返回文件路径
   */
  async exportMistakesCSV(ctx: common.UIAbilityContext): Promise<string> {
    const mistakes = await this.db.getAllMistakes();

    // CSV 表头
    const rows: string[] = [
      '题目,选项A,选项B,选项C,选项D,正确答案,我的答案,连续正确次数,最后练习时间'
    ];

    for (const m of mistakes) {
      const q = await this.db.getQuestionById(m.questionId);
      if (!q) continue;

      const row = [
        this.csvEscape(q.question),
        this.csvEscape(q.optionA ?? ''),
        this.csvEscape(q.optionB ?? ''),
        this.csvEscape(q.optionC ?? ''),
        this.csvEscape(q.optionD ?? ''),
        this.csvEscape(q.answer),
        this.csvEscape(m.myLastAnswer ?? ''),
        String(m.consecutiveCorrect),
        m.lastPracticeTime ?? '',
      ].join(',');
      rows.push(row);
    }

    const csv      = '\uFEFF' + rows.join('\r\n'); // BOM 保证 Excel 正确识别 UTF-8
    const fileName = 'mistakes_' + this.dateTag() + '.csv';
    const filePath = ctx.filesDir + '/' + fileName;

    const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, csv);
    fs.closeSync(file);

    return filePath;
  }

  // ─────────────────── 分享文件 ───────────────────

  /**
   * 调用系统分享，将指定文件分享出去（可分享到手机文件管理器/邮件/蓝牙等）
   */
  async shareFile(ctx: common.UIAbilityContext, filePath: string): Promise<void> {
    const want = {
      action:     'ohos.want.action.sendData',
      type:       '*/*',
      parameters: {
        'ability.params.stream': filePath,
      },
    };
    await ctx.startAbility(want);
  }

  // ─────────────────── 工具方法 ───────────────────

  /** 安全地将 ArrayBuffer 转为 UTF-8 字符串（避免大文件栈溢出） */
  private arrayBufferToString(buf: ArrayBuffer): string {
    const CHUNK = 8192;
    const uint8 = new Uint8Array(buf);
    let result = '';
    for (let i = 0; i < uint8.length; i += CHUNK) {
      result += String.fromCharCode(...uint8.subarray(i, i + CHUNK));
    }
    return result;
  }

  private dateTag(): string {
    const d = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}`;
  }

  private csvEscape(s: string): string {
    if (!s) return '';
    // 含逗号、引号或换行时包裹双引号
    if (s.includes(',') || s.includes('"') || s.includes('\n')) {
      return '"' + s.replace(/"/g, '""') + '"';
    }
    return s;
  }
}
