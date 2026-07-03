import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import preferences from '@ohos.data.preferences';
import {
  QuestionBank, Question, QuestionType, Difficulty,
  PracticeSession, PracticeMode, SessionStatus,
  AnswerRecord, AnswerStatus, QuestionStat,
  PracticeConfig, MistakeItem
} from '../model/Models';

const TAG = 'DatabaseService';
const DB_NAME = 'quiz.db';
const DB_VERSION = 1;
const PREF_NAME = 'quiz_settings';

// ─── 建表 SQL ──────────────────────────────────────────────────

const SQL_CREATE_BANKS = `
CREATE TABLE IF NOT EXISTS question_banks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL,
  description TEXT    DEFAULT '',
  file_name   TEXT    DEFAULT '',
  total_count INTEGER DEFAULT 0,
  created_at  INTEGER NOT NULL DEFAULT (strftime('%s','now')),
  updated_at  INTEGER NOT NULL DEFAULT (strftime('%s','now'))
)`;

const SQL_CREATE_QUESTIONS = `
CREATE TABLE IF NOT EXISTS questions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  bank_id     INTEGER NOT NULL REFERENCES question_banks(id) ON DELETE CASCADE,
  seq_no      INTEGER NOT NULL DEFAULT 0,
  type        TEXT    NOT NULL DEFAULT 'single',
  question    TEXT    NOT NULL,
  option_a    TEXT    DEFAULT '',
  option_b    TEXT    DEFAULT '',
  option_c    TEXT    DEFAULT '',
  option_d    TEXT    DEFAULT '',
  option_e    TEXT    DEFAULT '',
  answer      TEXT    NOT NULL,
  explanation TEXT    DEFAULT '',
  category    TEXT    DEFAULT '',
  difficulty  INTEGER DEFAULT 2,
  score       REAL    DEFAULT 1.0,
  is_starred  INTEGER DEFAULT 0,
  is_flagged  INTEGER DEFAULT 0,
  user_note   TEXT    DEFAULT '',
  created_at  INTEGER NOT NULL DEFAULT (strftime('%s','now'))
)`;

const SQL_CREATE_SESSIONS = `
CREATE TABLE IF NOT EXISTS practice_sessions (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  bank_id       INTEGER NOT NULL REFERENCES question_banks(id) ON DELETE CASCADE,
  mode          TEXT    NOT NULL DEFAULT 'random',
  config_json   TEXT    DEFAULT '{}',
  total_count   INTEGER NOT NULL DEFAULT 0,
  correct_count INTEGER DEFAULT 0,
  duration_sec  INTEGER DEFAULT 0,
  total_score   REAL    DEFAULT 0,
  status        TEXT    DEFAULT 'ongoing',
  started_at    INTEGER NOT NULL DEFAULT (strftime('%s','now')),
  finished_at   INTEGER DEFAULT 0
)`;

const SQL_CREATE_ANSWERS = `
CREATE TABLE IF NOT EXISTS answer_records (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id    INTEGER NOT NULL REFERENCES practice_sessions(id) ON DELETE CASCADE,
  question_id   INTEGER NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  user_answer   TEXT    DEFAULT '',
  is_correct    INTEGER NOT NULL DEFAULT 0,
  time_spent_ms INTEGER DEFAULT 0,
  answered_at   INTEGER NOT NULL DEFAULT (strftime('%s','now'))
)`;

const SQL_CREATE_STATS = `
CREATE TABLE IF NOT EXISTS question_stats (
  question_id   INTEGER PRIMARY KEY REFERENCES questions(id) ON DELETE CASCADE,
  attempt_count INTEGER DEFAULT 0,
  correct_count INTEGER DEFAULT 0,
  last_answered INTEGER DEFAULT 0,
  updated_at    INTEGER NOT NULL DEFAULT (strftime('%s','now'))
)`;

const SQL_CREATE_INDEXES = [
  `CREATE INDEX IF NOT EXISTS idx_questions_bank     ON questions(bank_id)`,
  `CREATE INDEX IF NOT EXISTS idx_questions_category ON questions(bank_id, category)`,
  `CREATE INDEX IF NOT EXISTS idx_questions_type     ON questions(bank_id, type)`,
  `CREATE INDEX IF NOT EXISTS idx_answer_session     ON answer_records(session_id)`,
  `CREATE INDEX IF NOT EXISTS idx_answer_question    ON answer_records(question_id)`,
  `CREATE INDEX IF NOT EXISTS idx_session_bank       ON practice_sessions(bank_id)`,
];

const SQL_CREATE_MISTAKES = `
CREATE TABLE IF NOT EXISTS mistakes (
  question_id          INTEGER PRIMARY KEY REFERENCES questions(id) ON DELETE CASCADE,
  bank_id              INTEGER NOT NULL,
  wrong_count          INTEGER DEFAULT 1,
  consecutive_correct  INTEGER DEFAULT 0,
  my_last_answer       TEXT    DEFAULT '',
  last_practice_time   TEXT    DEFAULT '',
  added_at             TEXT    DEFAULT (datetime('now','localtime')),
  updated_at           TEXT    DEFAULT (datetime('now','localtime'))
)`;

// ─── DatabaseService 单例 ──────────────────────────────────────

export class DatabaseService {
  private static instance: DatabaseService;
  private store: relationalStore.RdbStore | null = null;
  private pref: preferences.Preferences | null = null;
  /** 错题自动移出阈值（缓存值，由 loadAutoRemoveThreshold 加载） */
  private _autoRemoveThreshold: number = 3;

  private constructor() {}

  static getInstance(): DatabaseService {
    if (!DatabaseService.instance) {
      DatabaseService.instance = new DatabaseService();
    }
    return DatabaseService.instance;
  }

  /** 初始化（在 EntryAbility.onCreate 调用）*/
  async init(context: common.UIAbilityContext): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.createTables();
    hilog.info(0x0000, TAG, 'DB 初始化完成');
    // 异步加载用户设置的阈值（不阻塞初始化）
    this.loadAutoRemoveThreshold(context);
  }

  /** 从 Preferences 加载错题自动移出阈值 */
  private async loadAutoRemoveThreshold(context: common.UIAbilityContext): Promise<void> {
    try {
      this.pref = await preferences.getPreferences(context, PREF_NAME);
      this._autoRemoveThreshold = await this.pref.get('autoRemove', 3) as number;
    } catch {}
  }

  /** 获取当前错题自动移出阈值 */
  get autoRemoveThreshold(): number {
    return this._autoRemoveThreshold;
  }

  /** 同步用户设置的阈值（由 SettingsPage 调用） */
  syncAutoRemoveThreshold(threshold: number): void {
    this._autoRemoveThreshold = threshold;
  }

  private async createTables(): Promise<void> {
    if (!this.store) throw new Error('DB 未初始化');
    const sqls = [
      SQL_CREATE_BANKS,
      SQL_CREATE_QUESTIONS,
      SQL_CREATE_SESSIONS,
      SQL_CREATE_ANSWERS,
      SQL_CREATE_STATS,
      SQL_CREATE_MISTAKES,
      ...SQL_CREATE_INDEXES,
    ];
    for (const sql of sqls) {
      await this.store.executeSql(sql.trim());
    }
  }

  close(): void {
    if (this.store) {
      this.store.close();
      this.store = null;
    }
  }

  private getStore(): relationalStore.RdbStore {
    if (!this.store) throw new Error('DB 未初始化，请先调用 init()');
    return this.store;
  }

  // ══════════════════════════════════════════════════
  // 题库 CRUD
  // ══════════════════════════════════════════════════

  /** 插入题库，返回新 ID */
  async insertBank(name: string, description: string, fileName: string): Promise<number> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = {
      name, description, file_name: fileName,
      total_count: 0, created_at: now, updated_at: now,
    };
    return await this.getStore().insert('question_banks', values);
  }

  /** 查询所有题库（含统计） */
  async getAllBanks(): Promise<QuestionBank[]> {
    const sql = `
      SELECT b.*,
             COUNT(DISTINCT s.id)                                   AS practice_count,
             AVG(CASE WHEN s.total_count > 0
                      THEN CAST(s.correct_count AS REAL) / s.total_count END) AS avg_correct_rate,
             MAX(s.started_at)                                      AS last_practice_at
      FROM question_banks b
      LEFT JOIN practice_sessions s ON s.bank_id = b.id AND s.status = 'completed'
      GROUP BY b.id
      ORDER BY b.updated_at DESC`;
    const result = await this.getStore().querySql(sql);
    const banks: QuestionBank[] = [];
    while (result.goToNextRow()) {
      banks.push(this.rowToBank(result));
    }
    result.close();
    return banks;
  }

  /** 根据 ID 查询题库 */
  async getBankById(id: number): Promise<QuestionBank | null> {
    const predicates = new relationalStore.RdbPredicates('question_banks');
    predicates.equalTo('id', id);
    const result = await this.getStore().query(predicates);
    if (result.goToFirstRow()) {
      const bank = this.rowToBank(result);
      result.close();
      return bank;
    }
    result.close();
    return null;
  }

  /** 更新题库信息 */
  async updateBank(id: number, name: string, description: string): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = { name, description, updated_at: now };
    const predicates = new relationalStore.RdbPredicates('question_banks');
    predicates.equalTo('id', id);
    await this.getStore().update(values, predicates);
  }

  /** 删除题库（级联删除题目/记录） */
  async deleteBank(id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('question_banks');
    predicates.equalTo('id', id);
    await this.getStore().delete(predicates);
  }

  /** 更新题库题目数量 */
  async updateBankCount(bankId: number): Promise<void> {
    await this.getStore().executeSql(
      `UPDATE question_banks SET total_count = (SELECT COUNT(*) FROM questions WHERE bank_id = ?), updated_at = ? WHERE id = ?`,
      [bankId, Math.floor(Date.now() / 1000), bankId]
    );
  }

  private rowToBank(result: relationalStore.ResultSet): QuestionBank {
    return {
      id:              result.getLong(result.getColumnIndex('id')),
      name:            result.getString(result.getColumnIndex('name')),
      description:     result.getString(result.getColumnIndex('description')),
      fileName:        result.getString(result.getColumnIndex('file_name')),
      totalCount:      result.getLong(result.getColumnIndex('total_count')),
      createdAt:       result.getLong(result.getColumnIndex('created_at')),
      updatedAt:       result.getLong(result.getColumnIndex('updated_at')),
      practiceCount:   result.columnNames.includes('practice_count') ? result.getLong(result.getColumnIndex('practice_count')) : 0,
      avgCorrectRate:  result.columnNames.includes('avg_correct_rate') ? result.getDouble(result.getColumnIndex('avg_correct_rate')) : 0,
      lastPracticeAt:  result.columnNames.includes('last_practice_at') ? result.getLong(result.getColumnIndex('last_practice_at')) : 0,
    };
  }

  // ══════════════════════════════════════════════════
  // 题目 CRUD
  // ══════════════════════════════════════════════════

  /** 批量插入题目（事务） */
  async insertQuestions(bankId: number, questions: Partial<Question>[]): Promise<void> {
    const store = this.getStore();
    await store.beginTransaction();
    try {
      const now = Math.floor(Date.now() / 1000);
      for (const q of questions) {
        const values: relationalStore.ValuesBucket = {
          bank_id:     bankId,
          seq_no:      q.seqNo ?? 0,
          type:        q.type ?? QuestionType.SINGLE,
          question:    q.question ?? '',
          option_a:    q.optionA ?? '',
          option_b:    q.optionB ?? '',
          option_c:    q.optionC ?? '',
          option_d:    q.optionD ?? '',
          option_e:    q.optionE ?? '',
          answer:      q.answer ?? '',
          explanation: q.explanation ?? '',
          category:    q.category ?? '',
          difficulty:  q.difficulty ?? Difficulty.MEDIUM,
          score:       q.score ?? 1.0,
          is_starred:  0,
          is_flagged:  0,
          user_note:   '',
          created_at:  now,
        };
        await store.insert('questions', values);
      }
      await store.commit();
    } catch (err) {
      await store.rollBack();
      throw err;
    }
  }

  /** 查询题库下所有题目（支持筛选） */
  async getQuestions(bankId: number, options?: {
    types?: QuestionType[];
    categories?: string[];
    difficulties?: Difficulty[];
    limit?: number;
    offset?: number;
  }): Promise<Question[]> {
    let sql = `SELECT q.*, qs.attempt_count, qs.correct_count, qs.last_answered
               FROM questions q
               LEFT JOIN question_stats qs ON qs.question_id = q.id
               WHERE q.bank_id = ?`;
    const args: relationalStore.ValueType[] = [bankId];

    if (options?.types && options.types.length > 0) {
      sql += ` AND q.type IN (${options.types.map(() => '?').join(',')})`;
      args.push(...options.types);
    }
    if (options?.categories && options.categories.length > 0) {
      sql += ` AND q.category IN (${options.categories.map(() => '?').join(',')})`;
      args.push(...options.categories);
    }
    if (options?.difficulties && options.difficulties.length > 0) {
      sql += ` AND q.difficulty IN (${options.difficulties.map(() => '?').join(',')})`;
      args.push(...options.difficulties);
    }
    sql += ` ORDER BY q.seq_no ASC`;
    if (options?.limit) {
      sql += ` LIMIT ? OFFSET ?`;
      args.push(options.limit, options.offset ?? 0);
    }

    const result = await this.getStore().querySql(sql, args);
    const questions: Question[] = [];
    while (result.goToNextRow()) {
      questions.push(this.rowToQuestion(result));
    }
    result.close();
    return questions;
  }

  /** 查询错题（在任意会话中答错过，且从未连续3次全对） */
  async getMistakeQuestions(bankId?: number): Promise<Question[]> {
    let sql = `
      SELECT DISTINCT q.*, qs.attempt_count, qs.correct_count, qs.last_answered
      FROM questions q
      JOIN question_stats qs ON qs.question_id = q.id
      WHERE qs.attempt_count > 0
        AND (CAST(qs.correct_count AS REAL) / qs.attempt_count) < 1.0`;
    const args: relationalStore.ValueType[] = [];
    if (bankId !== undefined) {
      sql += ` AND q.bank_id = ?`;
      args.push(bankId);
    }
    sql += ` ORDER BY qs.attempt_count DESC, q.bank_id ASC`;

    const result = await this.getStore().querySql(sql, args);
    const questions: Question[] = [];
    while (result.goToNextRow()) {
      questions.push(this.rowToQuestion(result));
    }
    result.close();
    return questions;
  }

  /** 查询错题专练用题目（从 mistakes 表取，含练习进度） */
  async getMistakeQuestionsV2(bankId?: number): Promise<Question[]> {
    let sql = `
      SELECT q.*, qs.attempt_count, qs.correct_count, qs.last_answered
      FROM mistakes m
      JOIN questions q ON q.id = m.question_id
      LEFT JOIN question_stats qs ON qs.question_id = q.id`;
    const args: relationalStore.ValueType[] = [];
    // bankId 为 0 时表示全题库错题，取所有错题
    if (bankId !== undefined && bankId > 0) {
      sql += ` WHERE m.bank_id = ?`;
      args.push(bankId);
    }
    sql += ` ORDER BY m.updated_at DESC`;

    const result = await this.getStore().querySql(sql, args);
    const questions: Question[] = [];
    while (result.goToNextRow()) {
      questions.push(this.rowToQuestion(result));
    }
    result.close();
    return questions;
  }

  /** 获取题库分类列表 */
  async getCategories(bankId: number): Promise<string[]> {
    const sql = `SELECT DISTINCT category FROM questions WHERE bank_id = ? AND category != '' ORDER BY category`;
    const result = await this.getStore().querySql(sql, [bankId]);
    const cats: string[] = [];
    while (result.goToNextRow()) {
      cats.push(result.getString(0));
    }
    result.close();
    return cats;
  }

  /** 删除单道题目 */
  async deleteQuestionById(id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('questions');
    predicates.equalTo('id', id);
    await this.getStore().delete(predicates);
  }

  /** 更新题目收藏/标记/笔记 */
  async updateQuestionMeta(id: number, data: { isStarred?: boolean; isFlagged?: boolean; userNote?: string }): Promise<void> {
    const values: relationalStore.ValuesBucket = {};
    if (data.isStarred !== undefined) values['is_starred'] = data.isStarred ? 1 : 0;
    if (data.isFlagged !== undefined) values['is_flagged'] = data.isFlagged ? 1 : 0;
    if (data.userNote  !== undefined) values['user_note']  = data.userNote;
    const predicates = new relationalStore.RdbPredicates('questions');
    predicates.equalTo('id', id);
    await this.getStore().update(values, predicates);
  }

  private rowToQuestion(result: relationalStore.ResultSet): Question {
    return {
      id:           result.getLong(result.getColumnIndex('id')),
      bankId:       result.getLong(result.getColumnIndex('bank_id')),
      seqNo:        result.getLong(result.getColumnIndex('seq_no')),
      type:         result.getString(result.getColumnIndex('type')) as QuestionType,
      question:     result.getString(result.getColumnIndex('question')),
      optionA:      result.getString(result.getColumnIndex('option_a')),
      optionB:      result.getString(result.getColumnIndex('option_b')),
      optionC:      result.getString(result.getColumnIndex('option_c')),
      optionD:      result.getString(result.getColumnIndex('option_d')),
      optionE:      result.getString(result.getColumnIndex('option_e')),
      answer:       result.getString(result.getColumnIndex('answer')),
      explanation:  result.getString(result.getColumnIndex('explanation')),
      category:     result.getString(result.getColumnIndex('category')),
      difficulty:   result.getLong(result.getColumnIndex('difficulty')) as Difficulty,
      score:        result.getDouble(result.getColumnIndex('score')),
      isStarred:    result.getLong(result.getColumnIndex('is_starred')) === 1,
      isFlagged:    result.getLong(result.getColumnIndex('is_flagged')) === 1,
      userNote:     result.getString(result.getColumnIndex('user_note')),
      createdAt:    result.getLong(result.getColumnIndex('created_at')),
      attemptCount: result.columnNames.includes('attempt_count') ? result.getLong(result.getColumnIndex('attempt_count')) : 0,
      correctCount: result.columnNames.includes('correct_count') ? result.getLong(result.getColumnIndex('correct_count')) : 0,
      lastAnswered: result.columnNames.includes('last_answered') ? result.getLong(result.getColumnIndex('last_answered')) : 0,
    };
  }

  // ══════════════════════════════════════════════════
  // 练习会话 CRUD
  // ══════════════════════════════════════════════════

  async insertSession(bankId: number, mode: PracticeMode, config: PracticeConfig, totalCount: number): Promise<number> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = {
      bank_id: bankId, mode,
      config_json: JSON.stringify(config),
      total_count: totalCount,
      correct_count: 0, duration_sec: 0, total_score: 0,
      status: SessionStatus.ONGOING,
      started_at: now, finished_at: 0,
    };
    return await this.getStore().insert('practice_sessions', values);
  }

  async finishSession(id: number, correctCount: number, durationSec: number, totalScore: number): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = {
      correct_count: correctCount,
      duration_sec: durationSec,
      total_score: totalScore,
      status: SessionStatus.COMPLETED,
      finished_at: now,
    };
    const predicates = new relationalStore.RdbPredicates('practice_sessions');
    predicates.equalTo('id', id);
    await this.getStore().update(values, predicates);
  }

  async abandonSession(id: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { status: SessionStatus.ABANDONED };
    const predicates = new relationalStore.RdbPredicates('practice_sessions');
    predicates.equalTo('id', id);
    await this.getStore().update(values, predicates);
  }

  async getSessions(limit: number = 50, bankId?: number): Promise<PracticeSession[]> {
    let sql = `
      SELECT s.*, b.name AS bank_name
      FROM practice_sessions s
      JOIN question_banks b ON b.id = s.bank_id
      WHERE s.status = 'completed'`;
    const args: relationalStore.ValueType[] = [];
    if (bankId !== undefined) { sql += ` AND s.bank_id = ?`; args.push(bankId); }
    sql += ` ORDER BY s.started_at DESC LIMIT ?`;
    args.push(limit);

    const result = await this.getStore().querySql(sql, args);
    const sessions: PracticeSession[] = [];
    while (result.goToNextRow()) {
      sessions.push(this.rowToSession(result));
    }
    result.close();
    return sessions;
  }

  private rowToSession(result: relationalStore.ResultSet): PracticeSession {
    const configStr = result.getString(result.getColumnIndex('config_json'));
    let config: PracticeConfig | undefined;
    try { config = JSON.parse(configStr); } catch {}
    return {
      id:           result.getLong(result.getColumnIndex('id')),
      bankId:       result.getLong(result.getColumnIndex('bank_id')),
      mode:         result.getString(result.getColumnIndex('mode')) as PracticeMode,
      configJson:   configStr,
      totalCount:   result.getLong(result.getColumnIndex('total_count')),
      correctCount: result.getLong(result.getColumnIndex('correct_count')),
      durationSec:  result.getLong(result.getColumnIndex('duration_sec')),
      totalScore:   result.getDouble(result.getColumnIndex('total_score')),
      status:       result.getString(result.getColumnIndex('status')) as SessionStatus,
      startedAt:    result.getLong(result.getColumnIndex('started_at')),
      finishedAt:   result.getLong(result.getColumnIndex('finished_at')),
      bankName:     result.columnNames.includes('bank_name') ? result.getString(result.getColumnIndex('bank_name')) : '',
      config,
    };
  }

  // ══════════════════════════════════════════════════
  // 答题记录 CRUD
  // ══════════════════════════════════════════════════

  async insertAnswer(sessionId: number, questionId: number, userAnswer: string, isCorrect: AnswerStatus, timeSpentMs: number): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = {
      session_id: sessionId, question_id: questionId,
      user_answer: userAnswer, is_correct: isCorrect,
      time_spent_ms: timeSpentMs, answered_at: now,
    };
    await this.getStore().insert('answer_records', values);
    // 更新统计缓存
    await this.upsertStat(questionId, isCorrect === AnswerStatus.CORRECT);
  }

  async getAnswersBySession(sessionId: number): Promise<AnswerRecord[]> {
    const sql = `
      SELECT ar.*, q.question, q.type, q.option_a, q.option_b, q.option_c, q.option_d, q.option_e,
             q.answer, q.explanation, q.category, q.difficulty, q.score
      FROM answer_records ar
      JOIN questions q ON q.id = ar.question_id
      WHERE ar.session_id = ?
      ORDER BY ar.answered_at ASC`;
    const result = await this.getStore().querySql(sql, [sessionId]);
    const records: AnswerRecord[] = [];
    while (result.goToNextRow()) {
      records.push({
        id:          result.getLong(result.getColumnIndex('id')),
        sessionId:   result.getLong(result.getColumnIndex('session_id')),
        questionId:  result.getLong(result.getColumnIndex('question_id')),
        userAnswer:  result.getString(result.getColumnIndex('user_answer')),
        isCorrect:   result.getLong(result.getColumnIndex('is_correct')) as AnswerStatus,
        timeSpentMs: result.getLong(result.getColumnIndex('time_spent_ms')),
        answeredAt:  result.getLong(result.getColumnIndex('answered_at')),
        question:    this.rowToQuestion(result),
      });
    }
    result.close();
    return records;
  }

  // ══════════════════════════════════════════════════
  // 统计缓存 Upsert
  // ══════════════════════════════════════════════════

  private async upsertStat(questionId: number, correct: boolean): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    await this.getStore().executeSql(
      `INSERT INTO question_stats(question_id, attempt_count, correct_count, last_answered, updated_at)
       VALUES(?, 1, ?, ?, ?)
       ON CONFLICT(question_id) DO UPDATE SET
         attempt_count = attempt_count + 1,
         correct_count = correct_count + ?,
         last_answered = ?,
         updated_at = ?`,
      [questionId, correct ? 1 : 0, now, now, correct ? 1 : 0, now, now]
    );
  }

  // ══════════════════════════════════════════════════
  // 数据分析查询
  // ══════════════════════════════════════════════════

  /** 近 N 天每日练习次数和正确率 */
  async getDailyStats(days: number = 14): Promise<Array<{ date: string; count: number; correctRate: number }>> {
    const cutoff = Math.floor(Date.now() / 1000) - days * 86400;
    const sql = `
      SELECT date(started_at, 'unixepoch', 'localtime')        AS date,
             COUNT(*)                                           AS count,
             AVG(CASE WHEN total_count > 0
                      THEN CAST(correct_count AS REAL) / total_count END) AS correct_rate
      FROM practice_sessions
      WHERE status = 'completed' AND started_at >= ?
      GROUP BY date
      ORDER BY date ASC`;
    const result = await this.getStore().querySql(sql, [cutoff]);
    const rows: Array<{ date: string; count: number; correctRate: number }> = [];
    while (result.goToNextRow()) {
      rows.push({
        date:        result.getString(0),
        count:       result.getLong(1),
        correctRate: result.getDouble(2),
      });
    }
    result.close();
    return rows;
  }

  /** 各分类正确率 */
  async getCategoryStats(bankId?: number): Promise<Array<{ category: string; attempts: number; correctRate: number }>> {
    let sql = `
      SELECT q.category,
             SUM(qs.attempt_count)                                AS attempts,
             AVG(CASE WHEN qs.attempt_count > 0
                      THEN CAST(qs.correct_count AS REAL) / qs.attempt_count END) AS correct_rate
      FROM questions q
      JOIN question_stats qs ON qs.question_id = q.id
      WHERE q.category != '' AND qs.attempt_count > 0`;
    const args: relationalStore.ValueType[] = [];
    if (bankId !== undefined) { sql += ` AND q.bank_id = ?`; args.push(bankId); }
    sql += ` GROUP BY q.category ORDER BY attempts DESC`;
    const result = await this.getStore().querySql(sql, args);
    const rows: Array<{ category: string; attempts: number; correctRate: number }> = [];
    while (result.goToNextRow()) {
      rows.push({ category: result.getString(0), attempts: result.getLong(1), correctRate: result.getDouble(2) });
    }
    result.close();
    return rows;
  }

  // ══════════════════════════════════════════════════
  // 备份 / 还原 相关
  // ══════════════════════════════════════════════════

  /** 获取所有 Session（含未完成），供备份使用 */
  async getAllSessions(): Promise<PracticeSession[]> {
    const sql = `
      SELECT s.*, b.name AS bank_name
      FROM practice_sessions s
      JOIN question_banks b ON b.id = s.bank_id
      ORDER BY s.started_at DESC`;
    const result = await this.getStore().querySql(sql);
    const sessions: PracticeSession[] = [];
    while (result.goToNextRow()) { sessions.push(this.rowToSession(result)); }
    result.close();
    return sessions;
  }

  /** 根据 sessionId 查全部答题记录 */
  async getAnswerRecords(sessionId: number): Promise<AnswerRecord[]> {
    const sql = `SELECT * FROM answer_records WHERE session_id = ? ORDER BY answered_at ASC`;
    const result = await this.getStore().querySql(sql, [sessionId]);
    const records: AnswerRecord[] = [];
    while (result.goToNextRow()) {
      records.push({
        id:          result.getLong(result.getColumnIndex('id')),
        sessionId:   result.getLong(result.getColumnIndex('session_id')),
        questionId:  result.getLong(result.getColumnIndex('question_id')),
        userAnswer:  result.getString(result.getColumnIndex('user_answer')),
        isCorrect:   result.getLong(result.getColumnIndex('is_correct')) as AnswerStatus,
        timeSpentMs: result.getLong(result.getColumnIndex('time_spent_ms')),
        answeredAt:  result.getLong(result.getColumnIndex('answered_at')),
      });
    }
    result.close();
    return records;
  }

  /** 根据题目 ID 列表批量查询题目（供结果页使用） */
  async getQuestionsByIds(ids: number[]): Promise<Question[]> {
    if (!ids || ids.length === 0) return [];
    const placeholders = ids.map(() => '?').join(',');
    const sql = `SELECT * FROM questions WHERE id IN (${placeholders})`;
    const result = await this.getStore().querySql(sql, ids);
    const questions: Question[] = [];
    while (result.goToNextRow()) {
      questions.push(this.rowToQuestion(result));
    }
    result.close();
    return questions;
  }

  /** 查询所有错题记录（mistakes 表） */
  async getAllMistakes(): Promise<MistakeItem[]> {
    const sql = `SELECT * FROM mistakes ORDER BY updated_at DESC`;
    try {
      const result = await this.getStore().querySql(sql);
      const list: MistakeItem[] = [];
      while (result.goToNextRow()) {
        list.push({
          questionId:          result.getLong(result.getColumnIndex('question_id')),
          bankId:              result.getLong(result.getColumnIndex('bank_id')),
          wrongCount:          result.getLong(result.getColumnIndex('wrong_count')),
          consecutiveCorrect:  result.getLong(result.getColumnIndex('consecutive_correct')),
          myLastAnswer:        result.getString(result.getColumnIndex('my_last_answer')),
          lastPracticeTime:    result.getString(result.getColumnIndex('last_practice_time')),
          addedAt:             result.getString(result.getColumnIndex('added_at')),
        });
      }
      result.close();
      return list;
    } catch {
      return [];
    }
  }

  /** 根据题目 ID 查单条题目 */
  async getQuestionById(id: number): Promise<Question | null> {
    const predicates = new relationalStore.RdbPredicates('questions');
    predicates.equalTo('id', id);
    const result = await this.getStore().query(predicates);
    if (result.goToFirstRow()) {
      const q = this.rowToQuestion(result);
      result.close();
      return q;
    }
    result.close();
    return null;
  }

  /**
   * 从备份数据批量还原（追加模式，跳过已存在的 ID）
   * 注：保持原 ID 关系，需先清空或使用 INSERT OR IGNORE
   */
  async restoreFromBackup(
    banks: QuestionBank[],
    questions: Question[],
    sessions: PracticeSession[],
    answerRecords: AnswerRecord[],
    mistakes: MistakeItem[],
  ): Promise<void> {
    const store = this.getStore();
    await store.beginTransaction();
    try {
      const now = Math.floor(Date.now() / 1000);

      for (const b of banks) {
        await store.executeSql(
          `INSERT OR IGNORE INTO question_banks(id,name,description,file_name,total_count,created_at,updated_at)
           VALUES(?,?,?,?,?,?,?)`,
          [b.id!, b.name, b.description ?? '', b.fileName ?? '', b.totalCount ?? 0, b.createdAt ?? now, b.updatedAt ?? now]
        );
      }

      for (const q of questions) {
        await store.executeSql(
          `INSERT OR IGNORE INTO questions(id,bank_id,seq_no,type,question,option_a,option_b,option_c,option_d,option_e,
           answer,explanation,category,difficulty,score,is_starred,is_flagged,user_note,created_at)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
          [q.id!, q.bankId, q.seqNo ?? 0, q.type, q.question,
           q.optionA ?? '', q.optionB ?? '', q.optionC ?? '', q.optionD ?? '', q.optionE ?? '',
           q.answer, q.explanation ?? '', q.category ?? '', q.difficulty ?? 2, q.score ?? 1.0,
           q.isStarred ? 1 : 0, q.isFlagged ? 1 : 0, q.userNote ?? '', q.createdAt ?? now]
        );
      }

      for (const s of sessions) {
        await store.executeSql(
          `INSERT OR IGNORE INTO practice_sessions(id,bank_id,mode,config_json,total_count,correct_count,
           duration_sec,total_score,status,started_at,finished_at)
           VALUES(?,?,?,?,?,?,?,?,?,?,?)`,
          [s.id!, s.bankId, s.mode, s.configJson ?? '{}', s.totalCount, s.correctCount ?? 0,
           s.durationSec ?? 0, s.totalScore ?? 0, s.status, s.startedAt ?? now, s.finishedAt ?? 0]
        );
      }

      for (const ar of answerRecords) {
        await store.executeSql(
          `INSERT OR IGNORE INTO answer_records(id,session_id,question_id,user_answer,is_correct,time_spent_ms,answered_at)
           VALUES(?,?,?,?,?,?,?)`,
          [ar.id!, ar.sessionId, ar.questionId, ar.userAnswer ?? '', ar.isCorrect, ar.timeSpentMs ?? 0, ar.answeredAt ?? now]
        );
      }

      for (const m of mistakes) {
        await store.executeSql(
          `INSERT OR IGNORE INTO mistakes(question_id,bank_id,wrong_count,consecutive_correct,my_last_answer,last_practice_time,added_at,updated_at)
           VALUES(?,?,?,?,?,?,?,?)`,
          [m.questionId, m.bankId, m.wrongCount, m.consecutiveCorrect,
           m.myLastAnswer ?? '', m.lastPracticeTime ?? '', m.addedAt ?? '', m.addedAt ?? '']
        );
      }

      await store.commit();
    } catch (err) {
      await store.rollBack();
      throw err;
    }
  }

  /** 清除所有答题记录（保留题库和题目） */
  async clearAllHistory(): Promise<void> {
    const store = this.getStore();
    await store.beginTransaction();
    try {
      await store.executeSql(`DELETE FROM answer_records`);
      await store.executeSql(`DELETE FROM practice_sessions`);
      await store.executeSql(`DELETE FROM question_stats`);
      await store.executeSql(`DELETE FROM mistakes`);
      await store.commit();
    } catch (err) {
      await store.rollBack();
      throw err;
    }
  }

  // ══════════════════════════════════════════════════
  // 错题本 CRUD
  // ══════════════════════════════════════════════════

  /** 答错时更新/插入错题记录 */
  async upsertMistake(questionId: number, bankId: number, myAnswer: string): Promise<void> {
    const now = new Date().toISOString();
    await this.getStore().executeSql(
      `INSERT INTO mistakes(question_id, bank_id, wrong_count, consecutive_correct, my_last_answer, last_practice_time, added_at, updated_at)
       VALUES(?, ?, 1, 0, ?, ?, ?, ?)
       ON CONFLICT(question_id) DO UPDATE SET
         wrong_count         = wrong_count + 1,
         consecutive_correct = 0,
         my_last_answer      = ?,
         last_practice_time  = ?,
         updated_at          = ?`,
      [questionId, bankId, myAnswer, now, now, now, myAnswer, now, now]
    );
  }

  /** 答对时更新连续正确次数，连续≥阈值时自动移出 */
  async onCorrectAnswer(questionId: number, threshold: number = 3): Promise<void> {
    const now = new Date().toISOString();
    // 先加 1
    await this.getStore().executeSql(
      `UPDATE mistakes SET consecutive_correct = consecutive_correct + 1, last_practice_time = ?, updated_at = ?
       WHERE question_id = ?`,
      [now, now, questionId]
    );
    // 超过阈值则移出错题本
    await this.getStore().executeSql(
      `DELETE FROM mistakes WHERE question_id = ? AND consecutive_correct >= ?`,
      [questionId, threshold]
    );
  }

  /** 手动从错题本移除 */
  async removeMistake(questionId: number): Promise<void> {
    await this.getStore().executeSql(`DELETE FROM mistakes WHERE question_id = ?`, [questionId]);
  }

  /** 查询错题本（含题目信息） */
  async getMistakesWithQuestions(bankId?: number): Promise<MistakeItem[]> {
    let sql = `
      SELECT m.*, q.question, q.type, q.option_a, q.option_b, q.option_c, q.option_d, q.option_e,
             q.answer, q.explanation, q.category, q.difficulty, q.score,
             q.is_starred, q.is_flagged, q.user_note, q.seq_no, q.bank_id AS q_bank_id, q.created_at AS q_created_at
      FROM mistakes m
      JOIN questions q ON q.id = m.question_id`;
    const args: relationalStore.ValueType[] = [];
    // bankId 为 0 时表示全库错题（不过滤）
    if (bankId !== undefined && bankId > 0) {
      sql += ` WHERE m.bank_id = ?`;
      args.push(bankId);
    }
    sql += ` ORDER BY m.updated_at DESC`;

    const result = await this.getStore().querySql(sql, args);
    const list: MistakeItem[] = [];
    while (result.goToNextRow()) {
      list.push({
        questionId:         result.getLong(result.getColumnIndex('question_id')),
        bankId:             result.getLong(result.getColumnIndex('bank_id')),
        wrongCount:         result.getLong(result.getColumnIndex('wrong_count')),
        consecutiveCorrect: result.getLong(result.getColumnIndex('consecutive_correct')),
        myLastAnswer:       result.getString(result.getColumnIndex('my_last_answer')),
        lastPracticeTime:   result.getString(result.getColumnIndex('last_practice_time')),
        addedAt:            result.getString(result.getColumnIndex('added_at')),
        question: {
          id:          result.getLong(result.getColumnIndex('question_id')),
          bankId:      result.getLong(result.getColumnIndex('q_bank_id')),
          seqNo:       result.getLong(result.getColumnIndex('seq_no')),
          type:        result.getString(result.getColumnIndex('type')) as QuestionType,
          question:    result.getString(result.getColumnIndex('question')),
          optionA:     result.getString(result.getColumnIndex('option_a')),
          optionB:     result.getString(result.getColumnIndex('option_b')),
          optionC:     result.getString(result.getColumnIndex('option_c')),
          optionD:     result.getString(result.getColumnIndex('option_d')),
          optionE:     result.getString(result.getColumnIndex('option_e')),
          answer:      result.getString(result.getColumnIndex('answer')),
          explanation: result.getString(result.getColumnIndex('explanation')),
          category:    result.getString(result.getColumnIndex('category')),
          difficulty:  result.getLong(result.getColumnIndex('difficulty')) as Difficulty,
          score:       result.getDouble(result.getColumnIndex('score')),
          isStarred:   result.getLong(result.getColumnIndex('is_starred')) === 1,
          isFlagged:   result.getLong(result.getColumnIndex('is_flagged')) === 1,
          userNote:    result.getString(result.getColumnIndex('user_note')),
          createdAt:   result.getLong(result.getColumnIndex('q_created_at')),
        },
      });
    }
    result.close();
    return list;
  }

  /** 综合统计 */
  async getOverallStats(): Promise<{ totalSessions: number; totalQuestions: number; avgCorrectRate: number; totalTimeSec: number }> {
    const sql = `
      SELECT COUNT(*)                                    AS total_sessions,
             SUM(total_count)                            AS total_questions,
             AVG(CASE WHEN total_count > 0
                      THEN CAST(correct_count AS REAL) / total_count END) AS avg_correct_rate,
             SUM(duration_sec)                           AS total_time_sec
      FROM practice_sessions WHERE status = 'completed'`;
    const result = await this.getStore().querySql(sql);
    let stats = { totalSessions: 0, totalQuestions: 0, avgCorrectRate: 0, totalTimeSec: 0 };
    if (result.goToFirstRow()) {
      stats = {
        totalSessions:  result.getLong(0),
        totalQuestions: result.getLong(1),
        avgCorrectRate: result.getDouble(2),
        totalTimeSec:   result.getLong(3),
      };
    }
    result.close();
    return stats;
  }
}
