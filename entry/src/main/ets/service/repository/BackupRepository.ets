/**
 * BackupRepository.ets
 * 备份还原数据访问层
 *
 * 还原策略：覆盖模式——先清空全部业务表，再按备份顺序 INSERT。
 * 保证恢复后数据库与备份时完全一致，避免新旧数据混合导致关联错乱。
 */
import relationalStore from '@ohos.data.relationalStore';
import { QuestionBank, Question, PracticeSession, AnswerRecord, MistakeItem, QuestionType, Difficulty, PracticeMode, SessionStatus } from '../../model/Models';

export interface RestoreResult {
  inserted: number;
  skipped: number;
}

export class BackupRepository {
  constructor(private store: relationalStore.RdbStore) {}

  /** 校验备份中的主键 id：缺 id/非法 id 会导致外键关联错乱或插入 NULL 失败 */
  private requireId(id: number | undefined, kind: string): number {
    if (typeof id === 'number' && Number.isFinite(id) && id > 0) return id;
    throw new Error(`备份数据中${kind}缺少有效的 id`);
  }

  /** 全量还原（覆盖模式：先清空再插入，事务保证原子性） */
  async restore(banks: Partial<QuestionBank>[], questions: Partial<Question>[],
                sessions: Partial<PracticeSession>[], records: Partial<AnswerRecord>[],
                mistakes: Partial<MistakeItem>[]): Promise<RestoreResult> {
    let inserted = 0;
    let skipped = 0;
    await this.store.beginTransaction();
    try {
      // 先清空全部业务表（含 stats，由 FK CASCADE 辅助但显式删除更安全）
      await this.store.executeSql(`DELETE FROM answer_records`);
      await this.store.executeSql(`DELETE FROM practice_sessions`);
      await this.store.executeSql(`DELETE FROM question_stats`);
      await this.store.executeSql(`DELETE FROM mistakes`);
      await this.store.executeSql(`DELETE FROM questions`);
      await this.store.executeSql(`DELETE FROM question_banks`);

      const track = (rowCount: number) => {
        if (rowCount > 0) inserted++;
        else skipped++;
      };

      for (const b of banks) {
        const values: relationalStore.ValuesBucket = {
          id: this.requireId(b.id, '题库'), name: b.name ?? '', description: b.description ?? '',
          file_name: b.fileName ?? '', total_count: b.totalCount ?? 0,
          created_at: b.createdAt ?? 0, updated_at: b.updatedAt ?? 0,
        };
        const rowId = await this.store.insert('question_banks', values);
        track(rowId);
      }

      for (const q of questions) {
        const values: relationalStore.ValuesBucket = {
          id: this.requireId(q.id, '题目'),
          // NOT NULL 列必须显式兑底，undefined 会写 NULL 而非触发 DEFAULT
          bank_id: q.bankId ?? 0, seq_no: q.seqNo ?? 0,
          type: q.type ?? QuestionType.SINGLE, question: q.question ?? '',
          option_a: q.optionA ?? '', option_b: q.optionB ?? '', option_c: q.optionC ?? '',
          option_d: q.optionD ?? '', option_e: q.optionE ?? '',
          answer: q.answer ?? '', explanation: q.explanation ?? '',
          category: q.category ?? '', difficulty: q.difficulty ?? Difficulty.MEDIUM,
          score: q.score ?? 1.0, is_starred: q.isStarred ? 1 : 0,
          is_flagged: q.isFlagged ? 1 : 0, user_note: q.userNote ?? '',
          created_at: q.createdAt ?? 0,
        };
        const rowId = await this.store.insert('questions', values);
        track(rowId);
      }

      for (const s of sessions) {
        const values: relationalStore.ValuesBucket = {
          id: this.requireId(s.id, '练习会话'),
          bank_id: s.bankId ?? 0, mode: s.mode ?? PracticeMode.RANDOM,
          config_json: s.configJson ?? '', total_count: s.totalCount ?? 0,
          correct_count: s.correctCount ?? 0, duration_sec: s.durationSec ?? 0,
          total_score: s.totalScore ?? 0, status: s.status ?? SessionStatus.COMPLETED,
          started_at: s.startedAt ?? 0, finished_at: s.finishedAt ?? 0,
        };
        const rowId = await this.store.insert('practice_sessions', values);
        track(rowId);
      }

      for (const r of records) {
        const values: relationalStore.ValuesBucket = {
          id: this.requireId(r.id, '答题记录'),
          session_id: r.sessionId ?? 0, question_id: r.questionId ?? 0,
          user_answer: r.userAnswer ?? '', is_correct: r.isCorrect ?? 0,
          time_spent_ms: r.timeSpentMs ?? 0, answered_at: r.answeredAt ?? 0,
        };
        const rowId = await this.store.insert('answer_records', values);
        track(rowId);
      }

      for (const m of mistakes) {
        const values: relationalStore.ValuesBucket = {
          question_id: m.questionId ?? 0, bank_id: m.bankId ?? 0,
          wrong_count: m.wrongCount ?? 1, consecutive_correct: m.consecutiveCorrect ?? 0,
          my_last_answer: m.myLastAnswer ?? '', last_practice_time: m.lastPracticeTime ?? 0,
          added_at: m.addedAt ?? 0,
          updated_at: m.lastPracticeTime ?? m.addedAt ?? 0,
        };
        const rowId = await this.store.insert('mistakes', values);
        track(rowId);
      }

      await this.store.commit();
      return { inserted, skipped };
    } catch (err) {
      await this.store.rollBack();
      throw err;
    }
  }

  /** 清除全部答题/会话/统计/错题（保留题库与题目） */
  async clearAllHistory(): Promise<void> {
    await this.store.beginTransaction();
    try {
      await this.store.executeSql(`DELETE FROM answer_records`);
      await this.store.executeSql(`DELETE FROM practice_sessions`);
      await this.store.executeSql(`DELETE FROM question_stats`);
      await this.store.executeSql(`DELETE FROM mistakes`);
      await this.store.commit();
    } catch (err) {
      await this.store.rollBack();
      throw err;
    }
  }
}
