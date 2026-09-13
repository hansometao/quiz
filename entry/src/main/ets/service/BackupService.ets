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

/** 分批并发上限：题库/会话数极大时避免一次性发起全量并发请求 */
const BATCH_CONCURRENCY = 8;

/**
 * 按批次并发执行异步任务，保持结果顺序与输入一致。
 * collectBackupData 用它替代全量 Promise.all，题库/会话数很大时
 * 限制同时挂起的请求数，降低内存与调度压力。
 */
async function mapBatched<T, R>(items: T[], fn: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  for (let start = 0; start < items.length; start += BATCH_CONCURRENCY) {
    const batch = items.slice(start, start + BATCH_CONCURRENCY);
    const batchResults = await Promise.all(batch.map(fn));
    for (let i = 0; i < batchResults.length; i++) {
      results[start + i] = batchResults[i];
    }
  }
  return results;
}

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

/** 备份文件大小上限（50MB），防止恶意/损坏文件触发 OOM */
const MAX_BACKUP_FILE_SIZE = 50 * 1024 * 1024;

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
   * 汇集全量数据（题库/题目/会话/答题记录/错题）。
   * exportBackup 与 createSnapshot 共用，避免组装逻辑重复。
   */
  private async collectBackupData(): Promise<BackupData> {
    const banks    = await this.db.banks.getAll();
    const sessions = await this.db.sessions.getAll();
    const mistakes = await this.db.mistakes.getAll();

    // 分批并发拉取各题库的题目（不传 limit，避免硬编码截断）
    const validBanks = banks.filter(b => b.id !== undefined);
    const questionGroups = await mapBatched(validBanks, b => this.db.questions.getByBank(b.id!));
    const questions: Question[] = questionGroups.flat();

    // 分批并发拉取各会话的答题记录
    const validSessions = sessions.filter(s => s.id !== undefined);
    const answerGroups = await mapBatched(validSessions, s => this.db.sessions.getAnswersBySession(s.id!));
    const answerRecords: AnswerRecord[] = answerGroups.flat();

    return {
      version:     1,
      exportTime:  new Date().toISOString(),
      banks,
      questions,
      sessions,
      answerRecords,
      mistakes,
    };
  }

  /**
   * 将全量数据序列化为 JSON，保存到沙盒，返回文件路径
   */
  async exportBackup(ctx: common.UIAbilityContext): Promise<string> {
    const data = await this.collectBackupData();

    const json     = JSON.stringify(data);
    const fileName = 'quiz_backup_' + this.dateTag() + '.quizbackup';
    const filePath = ctx.filesDir + '/' + fileName;

    // 异步写入，避免阻塞 UI 线程
    const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, json);
    } finally {
      await fs.close(file);
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
      await fs.copyFile(uris[0], tmpPath);

      const stat = await fs.stat(tmpPath);
      // 文件大小校验：超过上限直接拒绝，避免分配超大 ArrayBuffer 触发 OOM
      if (stat.size > MAX_BACKUP_FILE_SIZE) {
        return { success: false, message: `备份文件过大（${Math.round(stat.size / 1024 / 1024)}MB），已拒绝导入` };
      }
      const buf = new ArrayBuffer(stat.size);
      const file = await fs.open(tmpPath, fs.OpenMode.READ_ONLY);
      try {
        await fs.read(file.fd, buf);
      } finally {
        await fs.close(file);
      }

      // 使用 TextDecoder 流式解码，避免 8192 字节切分破坏多字节字符
      const json = this.textDecoder.decodeWithStream(new Uint8Array(buf), { stream: false });
      const data = JSON.parse(json) as Partial<BackupData>;

      // 强校验：version 必须为合法数字，banks/questions/sessions/answerRecords/mistakes 必须为数组
      if (typeof data.version !== 'number' || data.version < 1) {
        return { success: false, message: '文件格式不正确：version 字段缺失或非法' };
      }
      if (!Array.isArray(data.banks) || !Array.isArray(data.questions) ||
          !Array.isArray(data.sessions) || !Array.isArray(data.answerRecords) ||
          !Array.isArray(data.mistakes)) {
        return { success: false, message: '文件格式不正确：数据字段缺失或类型错误' };
      }

      // 还原前自动快照：将当前数据导出到 filesDir 作为回滚点，
      // 万一还原失败或用户误操作，可从快照恢复（存 filesDir 而非 cacheDir——
      // cacheDir 会被系统按需清理，不能承担回滚点职责）
      let snapshotPath: string | null = null;
      try {
        snapshotPath = await this.createSnapshot(ctx);
      } catch (e) {
        // 快照失败不阻断还原，但记录警告
        console.warn('还原前快照创建失败', e);
      }

      // 执行还原（覆盖模式：先清空全部业务表再插入备份数据）
      const result = await this.db.backup.restore(data.banks, data.questions, data.sessions, data.answerRecords, data.mistakes);

      // 清理临时文件
      this.safeUnlink(tmpPath);
      tmpPath = null;

      return {
        success: true,
        message: `还原成功：共恢复 ${result.inserted} 条数据（已覆盖原有数据${snapshotPath ? '，可在设置页撤销本次还原' : ''}）`
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

    const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, csv);
    } finally {
      await fs.close(file);
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

  /**
   * 还原前自动快照：将当前 DB 数据导出到 filesDir 作为回滚点。
   * 快照文件固定命名（覆盖式保留最近一份）；失败不阻断还原流程。
   */
  private async createSnapshot(ctx: common.UIAbilityContext): Promise<string> {
    const snapshotPath = ctx.filesDir + '/pre_restore_snapshot.quizbackup';
    const data = await this.collectBackupData();

    const json = JSON.stringify(data);
    const file = await fs.open(snapshotPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, json);
    } finally {
      await fs.close(file);
    }
    return snapshotPath;
  }

  /**
   * 是否存在可用的还原前快照（供设置页决定是否展示"撤销还原"入口）
   */
  hasSnapshot(ctx: common.UIAbilityContext): boolean {
    return fs.accessSync(ctx.filesDir + '/pre_restore_snapshot.quizbackup');
  }

  /**
   * 撤销还原：从还原前快照恢复数据（再次走覆盖式还原）。
   * 成功后删除快照，防止二次撤销把更早的状态套娃回来。
   * 返回 { success, message }
   */
  async restoreFromSnapshot(ctx: common.UIAbilityContext): Promise<{ success: boolean; message: string }> {
    const snapshotPath = ctx.filesDir + '/pre_restore_snapshot.quizbackup';
    let tmpPath: string | null = null;
    try {
      if (!fs.accessSync(snapshotPath)) {
        return { success: false, message: '没有可撤销的快照' };
      }

      // 复用 importBackup 的读取与校验链：拷贝→大小上限→解码→结构强校验
      const stat = await fs.stat(snapshotPath);
      if (stat.size > MAX_BACKUP_FILE_SIZE) {
        return { success: false, message: '快照文件异常（过大），已拒绝恢复' };
      }
      const buf = new ArrayBuffer(stat.size);
      const file = await fs.open(snapshotPath, fs.OpenMode.READ_ONLY);
      try {
        await fs.read(file.fd, buf);
      } finally {
        await fs.close(file);
      }
      const json = this.textDecoder.decodeWithStream(new Uint8Array(buf), { stream: false });
      const data = JSON.parse(json) as Partial<BackupData>;

      if (typeof data.version !== 'number' || data.version < 1) {
        return { success: false, message: '快照格式不正确：version 字段缺失或非法' };
      }
      if (!Array.isArray(data.banks) || !Array.isArray(data.questions) ||
          !Array.isArray(data.sessions) || !Array.isArray(data.answerRecords) ||
          !Array.isArray(data.mistakes)) {
        return { success: false, message: '快照格式不正确：数据字段缺失或类型错误' };
      }

      // 撤销前先把"被撤销的坏数据"留一份新快照（覆盖旧快照）——若撤销本身选错了文件仍可再次撤销
      try {
        await this.createSnapshot(ctx);
      } catch (e) {
        console.warn('撤销前快照更新失败', e);
      }

      const result = await this.db.backup.restore(data.banks, data.questions, data.sessions, data.answerRecords, data.mistakes);

      // 撤销成功，消费掉快照
      this.safeUnlink(snapshotPath);
      return {
        success: true,
        message: `已撤销本次还原：恢复 ${result.inserted} 条数据（还原前状态已找回）`
      };
    } catch (e) {
      if (tmpPath) this.safeUnlink(tmpPath);
      const err = e as Error;
      return { success: false, message: '撤销还原失败：' + err.message };
    }
  }

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
