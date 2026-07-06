/**
 * MistakeRepository.ets
 * 错题本（mistakes）数据访问层
 *
 * 设计要点：
 * - 与 question_stats 分离，独立维护 wrong_count / consecutive_correct / my_last_answer
 * - 答错时 upsert，consecutive_correct 清零
 * - 答对时 consecutive_correct+1，达到阈值自动删除
 */
import relationalStore from '@ohos.data.relationalStore';
import { MistakeItem, Question } from '../../model/Models';
import { QuestionRepository } from './QuestionRepository';

export class MistakeRepository {
  constructor(private store: relationalStore.RdbStore) {}

  /** 答错时 upsert：wrong_count+1，consecutive_correct 清零 */
  async upsert(questionId: number, bankId: number, myAnswer: string): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    await this.store.executeSql(
      `INSERT INTO mistakes (question_id, bank_id, wrong_count, consecutive_correct, my_last_answer, last_practice_time, added_at, updated_at)
       VALUES (?, ?, 1, 0, ?, ?, ?, ?)
       ON CONFLICT(question_id) DO UPDATE SET
         wrong_count = wrong_count + 1,
         consecutive_correct = 0,
         my_last_answer = ?,
         last_practice_time = ?,
         updated_at = ?`,
      [questionId, bankId, myAnswer, now, now, now, myAnswer, now, now]
    );
  }

  /** 答对时 consecutive_correct+1，达到阈值自动删除（事务保证两步原子） */
  async onCorrectAnswer(questionId: number, threshold: number): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    await this.store.beginTransaction();
    try {
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
        [questionId, threshold]
      );
      await this.store.commit();
    } catch (err) {
      await this.store.rollBack();
      throw err;
    }
  }

  async remove(questionId: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('mistakes');
    predicates.equalTo('question_id', questionId);
    await this.store.delete(predicates);
  }

  /** 查询错题本（JOIN 题目） */
  async getWithQuestions(bankId?: number): Promise<MistakeItem[]> {
    // m.* 已含 m.bank_id；q 的字段用别名避免与 m.* 同名冲突（mistakes 表无 id 列，
    // rowToQuestion 读 'id' 会拿到 -1，因此必须显式选出 q.id AS q_id 并回填）
    let sql = `
      SELECT m.*, q.id AS q_id, q.bank_id AS q_bank_id, q.seq_no, q.type, q.question, q.option_a, q.option_b,
             q.option_c, q.option_d, q.option_e, q.answer, q.explanation, q.category,
             q.difficulty, q.score, q.is_starred, q.is_flagged, q.user_note, q.created_at,
             qs.attempt_count, qs.correct_count, qs.last_answered
      FROM mistakes m
      JOIN questions q ON q.id = m.question_id
      LEFT JOIN question_stats qs ON qs.question_id = q.id`;
    const args: relationalStore.ValueType[] = [];
    if (bankId !== undefined && bankId > 0) {
      sql += ` WHERE m.bank_id = ?`;
      args.push(bankId);
    }
    sql += ` ORDER BY m.updated_at DESC`;
    const result = await this.store.querySql(sql, args);
    const items: MistakeItem[] = [];
    const qRepo = new QuestionRepository(this.store);
    try {
      while (result.goToNextRow()) {
        const q = qRepo.rowToQuestion(result);
        // 别名 q_id / q_bank_id 覆盖 rowToQuestion 中 getColumnIndex('id'/'bank_id')
        // 命中 mistakes 表不存在列而得到的 0，避免 question.id 恒为 0 污染下游
        const qIdIdx = result.getColumnIndex('q_id');
        if (qIdIdx >= 0) q.id = result.getLong(qIdIdx);
        const qBankIdx = result.getColumnIndex('q_bank_id');
        if (qBankIdx >= 0) q.bankId = result.getLong(qBankIdx);
        items.push({
          questionId:          result.getLong(result.getColumnIndex('question_id')),
          bankId:              result.getLong(result.getColumnIndex('bank_id')),
          wrongCount:          result.getLong(result.getColumnIndex('wrong_count')),
          consecutiveCorrect:  result.getLong(result.getColumnIndex('consecutive_correct')),
          myLastAnswer:        result.getString(result.getColumnIndex('my_last_answer')),
          lastPracticeTime:    result.getLong(result.getColumnIndex('last_practice_time')),
          addedAt:             result.getLong(result.getColumnIndex('added_at')),
          question:            q,
        });
      }
    } finally {
      result.close();
    }
    return items;
  }

  /** 查询全部错题（供备份） */
  async getAll(): Promise<MistakeItem[]> {
    const sql = `SELECT * FROM mistakes`;
    const result = await this.store.querySql(sql);
    const items: MistakeItem[] = [];
    try {
      while (result.goToNextRow()) {
        items.push({
          questionId:          result.getLong(result.getColumnIndex('question_id')),
          bankId:              result.getLong(result.getColumnIndex('bank_id')),
          wrongCount:          result.getLong(result.getColumnIndex('wrong_count')),
          consecutiveCorrect:  result.getLong(result.getColumnIndex('consecutive_correct')),
          myLastAnswer:        result.getString(result.getColumnIndex('my_last_answer')),
          lastPracticeTime:    result.getLong(result.getColumnIndex('last_practice_time')),
          addedAt:             result.getLong(result.getColumnIndex('added_at')),
        });
      }
    } finally {
      result.close();
    }
    return items;
  }
}
