/**
 * SessionRepository.ets
 * 练习会话（practice_sessions）与答题记录（answer_records）数据访问层
 */
import relationalStore from '@ohos.data.relationalStore';
import { PracticeSession, AnswerRecord, PracticeMode, SessionStatus, PracticeConfig, normalizePracticeConfig } from '../../model/Models';
import { QuestionRepository } from './QuestionRepository';

/** 错题联动动作：与答题记录同事务执行，保证"落账 + 错题本"原子性（H3） */
export type MistakeAction =
  | { mode: 'wrong'; bankId: number; myAnswer: string }   // 答错：upsert 错题
  | { mode: 'correct'; threshold: number };               // 答对：连对+1，达阈值移出

export class SessionRepository {
  constructor(private store: relationalStore.RdbStore) {}

  /** 创建会话 */
  async insert(bankId: number, mode: PracticeMode, config: PracticeConfig, totalCount: number): Promise<number> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = {
      bank_id:        bankId,
      mode:           mode,
      config_json:    JSON.stringify(config),
      total_count:    totalCount,
      correct_count:  0,
      duration_sec:   0,
      total_score:    0,
      status:         SessionStatus.ONGOING,
      started_at:     now,
      finished_at:    0,
    };
    return await this.store.insert('practice_sessions', values);
  }

  /** 完成会话 */
  async finish(id: number, correctCount: number, durationSec: number, totalScore: number): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = {
      correct_count: correctCount,
      duration_sec:  durationSec,
      total_score:   totalScore,
      status:        SessionStatus.COMPLETED,
      finished_at:   now,
    };
    const predicates = new relationalStore.RdbPredicates('practice_sessions');
    predicates.equalTo('id', id);
    await this.store.update(values, predicates);
  }

  /** 放弃会话 */
  async abandon(id: number): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = { status: SessionStatus.ABANDONED, finished_at: now };
    const predicates = new relationalStore.RdbPredicates('practice_sessions');
    predicates.equalTo('id', id);
    await this.store.update(values, predicates);
  }

  /** 查询已完成会话（含题库名） */
  async getCompleted(limit: number, bankId?: number): Promise<PracticeSession[]> {
    let sql = `SELECT s.*, b.name AS bank_name
               FROM practice_sessions s
               LEFT JOIN question_banks b ON b.id = s.bank_id
               WHERE s.status = ?`;
    const args: relationalStore.ValueType[] = [SessionStatus.COMPLETED];
    if (bankId !== undefined && bankId > 0) {
      // bankId <= 0 视为“全部题库”（与 MistakeRepository 口径一致），避免查到空集
      sql += ` AND s.bank_id = ?`;
      args.push(bankId);
    }
    sql += ` ORDER BY s.finished_at DESC LIMIT ?`;
    args.push(limit);
    const result = await this.store.querySql(sql, args);
    const sessions: PracticeSession[] = [];
    try {
      while (result.goToNextRow()) {
        sessions.push(this.rowToSession(result));
      }
    } finally {
      result.close();
    }
    return sessions;
  }

  async getById(id: number): Promise<PracticeSession | null> {
    const sql = `SELECT s.*, b.name AS bank_name FROM practice_sessions s
                 LEFT JOIN question_banks b ON b.id = s.bank_id WHERE s.id = ?`;
    const result = await this.store.querySql(sql, [id]);
    try {
      if (result.goToFirstRow()) {
        return this.rowToSession(result);
      }
    } finally {
      result.close();
    }
    return null;
  }

  /** 查询全部会话（含未完成，供备份） */
  async getAll(): Promise<PracticeSession[]> {
    const sql = `SELECT * FROM practice_sessions`;
    const result = await this.store.querySql(sql);
    const sessions: PracticeSession[] = [];
    try {
      while (result.goToNextRow()) {
        sessions.push(this.rowToSession(result));
      }
    } finally {
      result.close();
    }
    return sessions;
  }

  /** 错题联动动作：与答题记录同事务执行，保证"落账 + 错题本"原子性（H3） */
  /** 插入答题记录并同步统计与错题本（单事务保证三步原子性） */
  async insertAnswer(sessionId: number, questionId: number, userAnswer: string,
                     isCorrect: number, timeSpentMs: number,
                     mistakeAction?: MistakeAction): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = {
      session_id:   sessionId,
      question_id:  questionId,
      user_answer:  userAnswer,
      is_correct:   isCorrect,
      time_spent_ms: timeSpentMs,
      answered_at:  now,
    };
    const correct = isCorrect === 1 ? 1 : 0;
    await this.store.beginTransaction();
    try {
      await this.store.insert('answer_records', values);
      await this.store.executeSql(
        `INSERT INTO question_stats (question_id, attempt_count, correct_count, last_answered, updated_at)
         VALUES (?, 1, ?, ?, ?)
         ON CONFLICT(question_id) DO UPDATE SET
           attempt_count = attempt_count + 1,
           correct_count = correct_count + ?,
           last_answered = ?,
           updated_at = ?`,
        [questionId, correct, now, now, correct, now, now]
      );
      // 错题联动与答题记录同事务（H3）：否则 A 成功 B 失败后重试会重复计账
      if (mistakeAction) {
        if (mistakeAction.mode === 'wrong') {
          await this.store.executeSql(
            `INSERT INTO mistakes (question_id, bank_id, wrong_count, consecutive_correct, my_last_answer, last_practice_time, added_at, updated_at)
             VALUES (?, ?, 1, 0, ?, ?, ?, ?)
             ON CONFLICT(question_id) DO UPDATE SET
               bank_id = ?,
               wrong_count = wrong_count + 1,
               consecutive_correct = 0,
               my_last_answer = ?,
               last_practice_time = ?,
               updated_at = ?`,
            [questionId, mistakeAction.bankId, mistakeAction.myAnswer, now, now, now,
             mistakeAction.bankId, mistakeAction.myAnswer, now, now]
          );
        } else {
          await this.store.executeSql(
            `UPDATE mistakes
               SET consecutive_correct = consecutive_correct + 1,
                   last_practice_time = ?,
                   updated_at = ?
             WHERE question_id = ?`,
            [now, now, questionId]
          );
          await this.store.executeSql(
            `DELETE FROM mistakes WHERE question_id = ? AND consecutive_correct >= ?`,
            [questionId, mistakeAction.threshold]
          );
        }
      }
      await this.store.commit();
    } catch (err) {
      await this.store.rollBack();
      throw err;
    }
  }

  /** 查询某会话全部答题（JOIN 题目） */
  async getAnswersBySession(sessionId: number): Promise<AnswerRecord[]> {
    // 显式列出 questions 全部字段，确保 rowToQuestion 能取到 id/is_starred 等列
    const sql = `SELECT ar.*, q.id AS q_id, q.bank_id, q.seq_no, q.type, q.question, q.option_a, q.option_b,
                        q.option_c, q.option_d, q.option_e, q.answer, q.explanation, q.category,
                        q.difficulty, q.score, q.is_starred, q.is_flagged, q.user_note, q.created_at
                 FROM answer_records ar
                 JOIN questions q ON q.id = ar.question_id
                 WHERE ar.session_id = ?
                 ORDER BY ar.answered_at ASC`;
    const result = await this.store.querySql(sql, [sessionId]);
    const records: AnswerRecord[] = [];
    const qRepo = new QuestionRepository(this.store);
    try {
      while (result.goToNextRow()) {
        const q = qRepo.rowToQuestion(result);
        // ar.* 与 q.id 同名，getColumnIndex('id') 命中 answer_records.id；
        // question 的真实 id 用别名 q_id 取回覆盖
        const qIdIdx = result.getColumnIndex('q_id');
        if (qIdIdx >= 0) q.id = result.getLong(qIdIdx);
        records.push({
          id:           result.getLong(result.getColumnIndex('id')),
          sessionId:    result.getLong(result.getColumnIndex('session_id')),
          questionId:   result.getLong(result.getColumnIndex('question_id')),
          userAnswer:   result.getString(result.getColumnIndex('user_answer')),
          isCorrect:    result.getLong(result.getColumnIndex('is_correct')),
          timeSpentMs:  result.getLong(result.getColumnIndex('time_spent_ms')),
          answeredAt:   result.getLong(result.getColumnIndex('answered_at')),
          question:     q,
        });
      }
    } finally {
      result.close();
    }
    return records;
  }

  /** 查询全部答题记录（供备份） */
  async getAllAnswers(): Promise<AnswerRecord[]> {
    const sql = `SELECT * FROM answer_records`;
    const result = await this.store.querySql(sql);
    const records: AnswerRecord[] = [];
    try {
      while (result.goToNextRow()) {
        records.push({
          id:           result.getLong(result.getColumnIndex('id')),
          sessionId:    result.getLong(result.getColumnIndex('session_id')),
          questionId:   result.getLong(result.getColumnIndex('question_id')),
          userAnswer:   result.getString(result.getColumnIndex('user_answer')),
          isCorrect:    result.getLong(result.getColumnIndex('is_correct')),
          timeSpentMs:  result.getLong(result.getColumnIndex('time_spent_ms')),
          answeredAt:   result.getLong(result.getColumnIndex('answered_at')),
        });
      }
    } finally {
      result.close();
    }
    return records;
  }

  private rowToSession(result: relationalStore.ResultSet): PracticeSession {
    const cfgJson = result.getString(result.getColumnIndex('config_json'));
    let cfg: PracticeConfig | undefined;
    if (cfgJson) {
      try {
        cfg = normalizePracticeConfig(JSON.parse(cfgJson) as Partial<PracticeConfig>);
      } catch {
        cfg = undefined;
      }
    }
    return {
      id:            result.getLong(result.getColumnIndex('id')),
      bankId:        result.getLong(result.getColumnIndex('bank_id')),
      mode:          result.getString(result.getColumnIndex('mode')) as PracticeMode,
      configJson:    cfgJson,
      config:        cfg,
      totalCount:    result.getLong(result.getColumnIndex('total_count')),
      correctCount:  result.getLong(result.getColumnIndex('correct_count')),
      durationSec:   result.getLong(result.getColumnIndex('duration_sec')),
      totalScore:    result.getDouble(result.getColumnIndex('total_score')),
      status:        result.getString(result.getColumnIndex('status')) as SessionStatus,
      startedAt:     result.getLong(result.getColumnIndex('started_at')),
      finishedAt:    result.getLong(result.getColumnIndex('finished_at')),
      bankName:      result.columnNames.includes('bank_name') ? result.getString(result.getColumnIndex('bank_name')) : '',
    };
  }
}
