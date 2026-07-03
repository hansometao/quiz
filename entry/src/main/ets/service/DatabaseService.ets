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
`;

export class DatabaseService {
  private static instance: DatabaseService;
  private store: relationalStore.RdbStore | null = null;
  private prefStore: preferences.Preferences | null = null;
  private _autoRemoveThreshold: number = DEFAULT_THRESHOLD;

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

  /** 初始化数据库与仓库 */
  async init(context: common.Context): Promise<void> {
    if (this.store) return;
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql(CREATE_SQL);
    await this.loadThreshold(context);
    this.banks    = new BankRepository(this.store);
    this.questions = new QuestionRepository(this.store);
    this.sessions = new SessionRepository(this.store);
    this.stats    = new StatsRepository(this.store);
    this.mistakes = new MistakeRepository(this.store);
    this.backup   = new BackupRepository(this.store);
    hilog.info(0x0000, TAG, 'database initialized');
  }

  private async loadThreshold(context: common.Context): Promise<void> {
    try {
      this.prefStore = await preferences.getPreferences(context, PREF_NAME);
      const v = await this.prefStore.get(KEY_AUTO_REMOVE_THRESHOLD, DEFAULT_THRESHOLD);
      this._autoRemoveThreshold = v as number;
    } catch (err) {
      hilog.warn(0x0000, TAG, `load threshold failed: ${JSON.stringify(err)}, use default`);
      this._autoRemoveThreshold = DEFAULT_THRESHOLD;
    }
  }

  /** 同步错题阈值（设置页调用） */
  async syncAutoRemoveThreshold(threshold: number): Promise<void> {
    this._autoRemoveThreshold = threshold;
    if (this.prefStore) {
      await this.prefStore.put(KEY_AUTO_REMOVE_THRESHOLD, threshold);
      await this.prefStore.flush();
    }
  }

  /** 关闭数据库 */
  async close(): Promise<void> {
    if (this.store) {
      try {
        await this.store.close();
      } catch (err) {
        hilog.warn(0x0000, TAG, `close db failed: ${JSON.stringify(err)}`);
      }
      this.store = null;
    }
  }
}
