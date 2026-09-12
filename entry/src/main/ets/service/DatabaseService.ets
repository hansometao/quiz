/**
 * DatabaseService.ets
 * 数据库服务（单例 / 薄外观）
 *
 * 职责：初始化 RDB Store、建表、加载配置；将各域操作委托给对应 Repository。
 * 各 Repository 持有同一个 RdbStore 实例，职责单一。
 *
 * 调用约定：
 *   const db = DatabaseService.getInstance();
 *   await db.init(context);
 *   const banks = await db.banks.getAll();
 *   const questions = await db.questions.getByBank(bankId);
 */
import common from '@ohos.app.ability.common';
import relationalStore from '@ohos.data.relationalStore';
import preferences from '@ohos.data.preferences';
import hilog from '@ohos.hilog';
import { BankRepository } from './repository/BankRepository';
import { QuestionRepository } from './repository/QuestionRepository';
import { SessionRepository } from './repository/SessionRepository';
import { StatsRepository } from './repository/StatsRepository';
import { MistakeRepository } from './repository/MistakeRepository';
import { BackupRepository } from './repository/BackupRepository';

const TAG = 'DatabaseService';
const DB_NAME = 'quiz.db';
const PREF_NAME = 'quiz_settings';
const KEY_AUTO_REMOVE_THRESHOLD = 'auto_remove_threshold';
const DEFAULT_THRESHOLD = 3;

const CREATE_SQL = `
  CREATE TABLE IF NOT EXISTS question_banks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    file_name TEXT,
    total_count INTEGER DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER
  );
  CREATE TABLE IF NOT EXISTS questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bank_id INTEGER NOT NULL,
    seq_no INTEGER DEFAULT 0,
    type TEXT NOT NULL,
    question TEXT NOT NULL,
    option_a TEXT, option_b TEXT, option_c TEXT, option_d TEXT, option_e TEXT,
    answer TEXT, explanation TEXT, category TEXT, difficulty INTEGER DEFAULT 2, score REAL DEFAULT 1.0,
    is_starred INTEGER DEFAULT 0, is_flagged INTEGER DEFAULT 0, user_note TEXT,
    created_at INTEGER,
    FOREIGN KEY (bank_id) REFERENCES question_banks(id) ON DELETE CASCADE
  );
  CREATE TABLE IF NOT EXISTS practice_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bank_id INTEGER NOT NULL,
    mode TEXT NOT NULL,
    config_json TEXT,
    total_count INTEGER DEFAULT 0,
    correct_count INTEGER DEFAULT 0,
    duration_sec INTEGER DEFAULT 0,
    total_score REAL DEFAULT 0,
    status TEXT DEFAULT 'ongoing',
    started_at INTEGER,
    finished_at INTEGER,
    FOREIGN KEY (bank_id) REFERENCES question_banks(id) ON DELETE CASCADE
  );
  CREATE TABLE IF NOT EXISTS answer_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    question_id INTEGER NOT NULL,
    user_answer TEXT,
    is_correct INTEGER DEFAULT 0,
    time_spent_ms INTEGER DEFAULT 0,
    answered_at INTEGER,
    FOREIGN KEY (session_id) REFERENCES practice_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
  );
  CREATE TABLE IF NOT EXISTS question_stats (
    question_id INTEGER PRIMARY KEY,
    attempt_count INTEGER DEFAULT 0,
    correct_count INTEGER DEFAULT 0,
    last_answered INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
  );
  CREATE TABLE IF NOT EXISTS mistakes (
    question_id INTEGER PRIMARY KEY,
    bank_id INTEGER NOT NULL,
    wrong_count INTEGER DEFAULT 1,
    consecutive_correct INTEGER DEFAULT 0,
    my_last_answer TEXT,
    last_practice_time INTEGER,
    added_at INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
  );
  CREATE INDEX IF NOT EXISTS idx_questions_bank ON questions(bank_id);
  CREATE INDEX IF NOT EXISTS idx_questions_category ON questions(bank_id, category);
  CREATE INDEX IF NOT EXISTS idx_questions_type ON questions(bank_id, type);
  CREATE INDEX IF NOT EXISTS idx_answer_session ON answer_records(session_id);
  CREATE INDEX IF NOT EXISTS idx_answer_question ON answer_records(question_id);
  CREATE INDEX IF NOT EXISTS idx_session_bank ON practice_sessions(bank_id);
  CREATE INDEX IF NOT EXISTS idx_session_finished ON practice_sessions(finished_at);
  CREATE INDEX IF NOT EXISTS idx_session_status_finished ON practice_sessions(status, finished_at);
  CREATE INDEX IF NOT EXISTS idx_mistakes_bank ON mistakes(bank_id);
  CREATE INDEX IF NOT EXISTS idx_mistakes_updated ON mistakes(updated_at);
`;

// 拆分为单条 DDL，逐条执行，规避多语句 executeSql 在不同实现下的可移植性风险
const DDL_STATEMENTS: string[] = CREATE_SQL.split(';').map(s => s.trim()).filter(s => s.length > 0);

export class DatabaseService {
  private static instance: DatabaseService;
  private store: relationalStore.RdbStore | null = null;
  private prefStore: preferences.Preferences | null = null;
  private _autoRemoveThreshold: number = DEFAULT_THRESHOLD;
  // 缓存进行中的 init Promise，避免并发调用重复建库与覆盖仓库实例
  private initPromise: Promise<void> | null = null;

  // 各域仓库
  public banks!: BankRepository;
  public questions!: QuestionRepository;
  public sessions!: SessionRepository;
  public stats!: StatsRepository;
  public mistakes!: MistakeRepository;
  public backup!: BackupRepository;

  private constructor() {}

  static getInstance(): DatabaseService {
    if (!DatabaseService.instance) {
      DatabaseService.instance = new DatabaseService();
    }
    return DatabaseService.instance;
  }

  get autoRemoveThreshold(): number {
    return this._autoRemoveThreshold;
  }

  /** 初始化数据库与仓库（幂等，并发安全） */
  init(context: common.Context): Promise<void> {
    // 必须先判 initPromise：doInit 内部 await getRdbStore 完成时会先赋值 this.store，
    // 但仓库实例尚未创建。若另一调用此时进来，仅凭 this.store 判断会绕过 initPromise
    // 直接返回，导致调用方拿到未初始化的 db.banks（undefined）。
    if (this.initPromise) return this.initPromise;
    if (this.store) return Promise.resolve();
    this.initPromise = this.doInit(context);
    return this.initPromise;
  }

  /** 等待数据库初始化完成。页面 load 方法调用此方法确保 DB 就绪后再查询，
   *  解决 EntryAbility.onCreate 异步 init 与 loadContent 同步触发页面加载的竞态 */
  ready(): Promise<void> {
    if (this.initPromise) return this.initPromise;
    if (this.store) return Promise.resolve();
    return Promise.reject(new Error('数据库尚未初始化'));
  }

  private async doInit(context: common.Context): Promise<void> {
    try {
      const config: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
      };
      const store = await relationalStore.getRdbStore(context, config);
      // 开启外键约束：SQLite 默认不启用，未开启则所有 ON DELETE CASCADE 失效。
      // 注意：PRAGMA 作用于单个连接——每次新建 RdbStore（连接）都必须重设；
      // 当前为单例长连接无问题，若未来改为连接池/多连接，需在每条连接建立时执行
      await store.executeSql('PRAGMA foreign_keys = ON;');
      // 逐条执行 DDL，规避多语句 executeSql 的可移植性风险
      for (const sql of DDL_STATEMENTS) {
        await store.executeSql(sql);
      }
      // 先加载阈值（不依赖 store 字段），再实例化仓库，最后才把 store 暴露给外部，
      // 确保一旦 this.store 非 null，所有仓库也必然就绪
      await this.loadThreshold(context);
      this.banks    = new BankRepository(store);
      this.questions = new QuestionRepository(store);
      this.sessions = new SessionRepository(store);
      this.stats    = new StatsRepository(store);
      this.mistakes = new MistakeRepository(store);
      this.backup   = new BackupRepository(store);
      this.store = store;
      hilog.info(0x0000, TAG, 'database initialized');
    } catch (err) {
      // 初始化失败：重置状态，允许后续重试
      this.initPromise = null;
      this.store = null;
      throw err;
    }
  }

  private async loadThreshold(context: common.Context): Promise<void> {
    try {
      this.prefStore = await preferences.getPreferences(context, PREF_NAME);
      const v = Number(await this.prefStore.get(KEY_AUTO_REMOVE_THRESHOLD, DEFAULT_THRESHOLD));
      // 读回值与写入端 syncAutoRemoveThreshold 保持同一约束（≥1 的整数），防御旧版本或外部写入的非法值
      this._autoRemoveThreshold = Number.isFinite(v) ? Math.max(1, Math.floor(v)) : DEFAULT_THRESHOLD;
    } catch (err) {
      hilog.warn(0x0000, TAG, `load threshold failed: ${JSON.stringify(err)}, use default`);
      this._autoRemoveThreshold = DEFAULT_THRESHOLD;
    }
  }

  /** 同步错题阈值（设置页调用）。先持久化再更新内存，避免持久化失败时内存与磁盘分叉 */
  async syncAutoRemoveThreshold(threshold: number): Promise<void> {
    // 强制约束：阈值必须为 ≥1 的整数。0 会导致 onCorrectAnswer 中
    // consecutive_correct >= 0 恒真，任意一次答对即清空错题本
    const v = Math.max(1, Math.floor(Number(threshold) || DEFAULT_THRESHOLD));
    if (this.prefStore) {
      await this.prefStore.put(KEY_AUTO_REMOVE_THRESHOLD, v);
      await this.prefStore.flush();
    }
    this._autoRemoveThreshold = v;
  }

  /** 关闭数据库。需重置 initPromise，否则下次 init() 会拿到已 resolved 的旧 Promise
   * 而绕过 doInit，导致使用已关闭的 store 抛错 */
  async close(): Promise<void> {
    if (this.store) {
      try {
        await this.store.close();
      } catch (err) {
        hilog.warn(0x0000, TAG, `close db failed: ${JSON.stringify(err)}`);
      }
      this.store = null;
    }
    // 同步释放偏好实例引用：close 后不应再向已废弃实例写入；
    // 下次 init 的 loadThreshold 会重新 getPreferences 获取
    this.prefStore = null;
    this.initPromise = null;
  }
}
