/**
 * BackupRepository.ets
 * 备份还原数据访问层
 *
 * 还原策略：INSERT OR IGNORE 追加模式，保留原 ID 关系，跳过已存在的 ID。
 * 返回 { inserted, skipped } 供用户提示。
 */
import relationalStore from '@ohos.data.relationalStore';
import { QuestionBank, Question, PracticeSession, AnswerRecord, MistakeItem, QuestionType, Difficulty, PracticeMode, SessionStatus } from '../../model/Models';

export interface RestoreResult {
  inserted: number;
  skipped: number;
}

export class BackupRepository {
  constructor(private store: relationalStore.RdbStore) {}

  /** 全量还原（事务批量 INSERT OR IGNORE） */
  async restore(banks: Partial<QuestionBank>[], questions: Partial<Question>[],
                sessions: Partial<PracticeSession>[], records: Partial<AnswerRecord>[],
                mistakes: Partial<MistakeItem>[]): Promise<RestoreResult> {
    let inserted = 0;
    let skipped = 0;
    await this.store.beginTransaction();
    try {
      const track = (rowCount: number) => {
        if (rowCount > 0) inserted++;
        else skipped++;
      };

      for (const b of banks) {
        const values: relationalStore.ValuesBucket = {
          id: b.id, name: b.name ?? '', description: b.description ?? '',
          file_name: b.fileName ?? '', total_count: b.totalCount ?? 0,
          created_at: b.createdAt ?? 0, updated_at: b.updatedAt ?? 0,
        };
        const rowId = await this.store.insertWithConflictResolution(
          'question_banks', values, relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
        track(rowId);
      }

      for (const q of questions) {
        const values: relationalStore.ValuesBucket = {
          id: q.id, bank_id: q.bankId, seq_no: q.seqNo ?? 0,
          // type/difficulty 为 NOT NULL 列，undefined 会写入 NULL 而非触发 DEFAULT，
          // 导致后续 WHERE difficulty IN (...) 筛选漏掉 NULL 行，必须显式兜底
          type: q.type ?? QuestionType.SINGLE, question: q.question ?? '',
          option_a: q.optionA ?? '', option_b: q.optionB ?? '', option_c: q.optionC ?? '',
          option_d: q.optionD ?? '', option_e: q.optionE ?? '',
          answer: q.answer ?? '', explanation: q.explanation ?? '',
          category: q.category ?? '', difficulty: q.difficulty ?? Difficulty.MEDIUM,
          score: q.score ?? 1.0, is_starred: q.isStarred ? 1 : 0,
          is_flagged: q.isFlagged ? 1 : 0, user_note: q.userNote ?? '',
          created_at: q.createdAt ?? 0,
        };
        const rowId = await this.store.insertWithConflictResolution(
          'questions', values, relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
        track(rowId);
      }

      for (const s of sessions) {
        const values: relationalStore.ValuesBucket = {
          id: s.id, bank_id: s.bankId, mode: s.mode ?? PracticeMode.RANDOM,
          config_json: s.configJson ?? '', total_count: s.totalCount ?? 0,
          correct_count: s.correctCount ?? 0, duration_sec: s.durationSec ?? 0,
          total_score: s.totalScore ?? 0, status: s.status ?? SessionStatus.COMPLETED,
          started_at: s.startedAt ?? 0, finished_at: s.finishedAt ?? 0,
        };
        const rowId = await this.store.insertWithConflictResolution(
          'practice_sessions', values, relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
        track(rowId);
      }

      for (const r of records) {
        const values: relationalStore.ValuesBucket = {
          id: r.id, session_id: r.sessionId, question_id: r.questionId,
          user_answer: r.userAnswer ?? '', is_correct: r.isCorrect ?? 0,
          time_spent_ms: r.timeSpentMs ?? 0, answered_at: r.answeredAt ?? 0,
        };
        const rowId = await this.store.insertWithConflictResolution(
          'answer_records', values, relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
        track(rowId);
      }

      for (const m of mistakes) {
        const values: relationalStore.ValuesBucket = {
          question_id: m.questionId, bank_id: m.bankId,
          wrong_count: m.wrongCount ?? 1, consecutive_correct: m.consecutiveCorrect ?? 0,
          my_last_answer: m.myLastAnswer ?? '', last_practice_time: m.lastPracticeTime ?? 0,
          added_at: m.addedAt ?? 0,
          // updated_at 用于 ORDER BY m.updated_at DESC 排序，应取最近活动时间；
          // 原实现误用 lastPracticeTime，导致从未练习过的错题排序失真
          updated_at: m.lastPracticeTime ?? m.addedAt ?? 0,
        };
        const rowId = await this.store.insertWithConflictResolution(
          'mistakes', values, relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
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
