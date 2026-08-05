/**
 * BackupService.ets
 * 备份 & 还原服务（单例）
 *   - exportBackup()     ：将全量数据打包为 JSON，写入沙盒 files/ 目录并返回路径供分享
 *   - importBackup()     ：读取用户选择的 .quizbackup 文件，校验后还原至 DB
 *   - exportMistakesCSV()：将错题导出为 CSV（含完整字段）
 */

import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
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
  private textDecoder = util.TextDecoder.create('utf-8');

  static getInstance(): BackupService {
    if (!BackupService.instance) {
      BackupService.instance = new BackupService();
    }
    return BackupService.instance;
  }

  // ─────────────────── 导出备份 ───────────────────

  /**
   * 将全量数据序列化为 JSON，保存到沙盒，返回文件路径
   * 并行拉取各题库题目与各会话答题记录，提升多题库场景下的导出速度。
   */
  async exportBackup(ctx: common.UIAbilityContext): Promise<string> {
    const banks    = await this.db.banks.getAll();
    const sessions = await this.db.sessions.getAll();
    const mistakes = await this.db.mistakes.getAll();

    // 并行拉取各题库的题目（不传 limit，避免硬编码截断）
    const questionGroups = await Promise.all(
      banks.filter(b => b.id !== undefined).map(b => this.db.questions.getByBank(b.id))
    );
    const questions: Question[] = questionGroups.flat();

    // 并行拉取各会话的答题记录
    const answerGroups = await Promise.all(
      sessions.filter(s => s.id !== undefined).map(s => this.db.sessions.getAnswersBySession(s.id))
    );
    const answerRecords: AnswerRecord[] = answerGroups.flat();

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
    try {
      fs.writeSync(file.fd, json);
    } finally {
      fs.closeSync(file);
    }

    return filePath;
  }

  // ─────────────────── 导入还原 ───────────────────

  /**
   * 弹出文件选择器，让用户选取 .quizbackup 文件，然后还原数据
   * 返回 { success, message }
   */
  async importBackup(ctx: common.UIAbilityContext): Promise<{ success: boolean; message: string }> {
    let tmpPath: string | null = null;
    try {
      const docPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await docPicker.select({
        maxSelectNumber: 1,
        defaultFilePathUri: 'file://docs/storage/Users/currentUser/Documents',
      });

      if (!uris || uris.length === 0) {
        return { success: false, message: '未选择文件' };
      }

      // 将 uri 拷贝到沙盒后读取（避免权限失效）
      tmpPath = ctx.cacheDir + '/import_tmp.quizbackup';
      fs.copyFileSync(uris[0], tmpPath);

      const stat = fs.statSync(tmpPath);
      const buf = new ArrayBuffer(stat.size);
      const file = fs.openSync(tmpPath, fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buf);
      } finally {
        fs.closeSync(file);
      }

      // 使用 TextDecoder 流式解码，避免 8192 字节切分破坏多字节字符
      const json = this.textDecoder.decodeWithStream(new Uint8Array(buf), { stream: false });
      const data = JSON.parse(json) as Partial<BackupData>;

      // 数据结构校验：必填字段与各数组存在性
      if (!data.version || !data.banks) {
        return { success: false, message: '文件格式不正确：缺少 version 或 banks 字段' };
      }
      const banks    = Array.isArray(data.banks)          ? data.banks          : [];
      const questions = Array.isArray(data.questions)      ? data.questions      : [];
      const sessions = Array.isArray(data.sessions)        ? data.sessions       : [];
      const records  = Array.isArray(data.answerRecords)  ? data.answerRecords  : [];
      const mistakes = Array.isArray(data.mistakes)       ? data.mistakes       : [];

      // 执行还原（追加模式，返回插入/跳过计数）
      const result = await this.db.backup.restore(banks, questions, sessions, records, mistakes);

      // 清理临时文件
      this.safeUnlink(tmpPath);
      tmpPath = null;

      return {
        success: true,
        message: `还原成功：共恢复 ${result.inserted} 条数据`
      };
    } catch (e) {
      if (tmpPath) this.safeUnlink(tmpPath);
      const err = e as Error;
      return { success: false, message: '还原失败：' + err.message };
    }
  }

  // ─────────────────── 导出错题 CSV ───────────────────

  /**
   * 将全部错题导出为 CSV（含完整字段），保存到沙盒，返回文件路径
   */
  async exportMistakesCSV(ctx: common.UIAbilityContext): Promise<string> {
    const mistakes = await this.db.mistakes.getWithQuestions();

    // CSV 表头（补全分类/难度/解析/错次等关键字段）
    const rows: string[] = [
      '题库ID,题目,题型,分类,难度,选项A,选项B,选项C,选项D,选项E,正确答案,解析,我的答案,错误次数,连续正确次数,最后练习时间'
    ];

    for (const m of mistakes) {
      const q = m.question;
      if (!q) continue;
      const row = [
        String(q.bankId),
        this.csvEscape(q.question),
        q.type,
        this.csvEscape(q.category ?? ''),
        String(q.difficulty),
        this.csvEscape(q.optionA ?? ''),
        this.csvEscape(q.optionB ?? ''),
        this.csvEscape(q.optionC ?? ''),
        this.csvEscape(q.optionD ?? ''),
        this.csvEscape(q.optionE ?? ''),
        this.csvEscape(q.answer),
        this.csvEscape(q.explanation ?? ''),
        this.csvEscape(m.myLastAnswer ?? ''),
        String(m.wrongCount),
        String(m.consecutiveCorrect),
        String(m.lastPracticeTime ?? 0),
      ].join(',');
      rows.push(row);
    }

    const csv      = '\uFEFF' + rows.join('\r\n'); // BOM 保证 Excel 正确识别 UTF-8
    const fileName = 'mistakes_' + this.dateTag() + '.csv';
    const filePath = ctx.filesDir + '/' + fileName;

    const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, csv);
    } finally {
      fs.closeSync(file);
    }

    return filePath;
  }

  // ─────────────────── 分享文件 ───────────────────

  /**
   * 调用系统分享，将指定文件分享出去
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

  private dateTag(): string {
    const d = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}`;
  }

  private csvEscape(s: string): string {
    if (!s) return '';
    // CSV 公式注入防护：以 = + - @ 制表符/回车 开头的字段会被 Excel 当作公式执行，
    // 在前面补单引号中和（Excel 打开时单引号不显示，仅作为文本前缀标记）
    let v = s;
    if (/^[=+\-@\t\r]/.test(v)) {
      v = "'" + v;
    }
    if (v.includes(',') || v.includes('"') || v.includes('\n') || v.includes('\r')) {
      return '"' + v.replace(/"/g, '""') + '"';
    }
    return v;
  }

  /** 安全删除临时文件，失败不抛错 */
  private safeUnlink(path: string): void {
    try { fs.unlinkSync(path); } catch {}
  }
}
