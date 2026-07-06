/**
 * StatsRepository.ets
 * 题目统计缓存（question_stats）与数据分析查询
 */
import relationalStore from '@ohos.data.relationalStore';

export interface DailyStat {
  date: string;
  count: number;
  correctRate: number;
}

export interface CategoryStat {
  category: string;
  attemptCount: number;
  correctCount: number;
  correctRate: number;
}

export interface OverallStat {
  totalSessions: number;
  totalQuestions: number;
  avgCorrectRate: number;
  totalDurationSec: number;
}

export class StatsRepository {
  constructor(private store: relationalStore.RdbStore) {}

  /** 近 N 天每日练习次数与正确率 */
  async getDailyStats(days: number = 14): Promise<DailyStat[]> {
    // 入参校验：避免 NaN/负数生成 '-NaN days' 让 strftime 静默失败返回空集
    const safeDays = Number.isFinite(days) && days > 0 ? Math.floor(days) : 14;
    const sql = `
      SELECT date(s.finished_at, 'unixepoch', 'localtime') AS date,
             COUNT(*)                                       AS count,
             SUM(CASE WHEN s.total_count > 0
                      THEN s.correct_count END) * 1.0
               / NULLIF(SUM(s.total_count), 0)              AS correct_rate
      FROM practice_sessions s
      WHERE s.status = 'completed'
        AND s.finished_at >= strftime('%s', 'now', ? )
      GROUP BY date
      ORDER BY date ASC`;
    // SQLite strftime 相对时间：'now','-N days' -> 这里传 '-${days} days'
    const result = await this.store.querySql(sql, [`-${safeDays} days`]);
    const stats: DailyStat[] = [];
    try {
      while (result.goToNextRow()) {
        stats.push({
          date:        result.getString(result.getColumnIndex('date')),
          count:       result.getLong(result.getColumnIndex('count')),
          // NULLIF 在 SUM=0 时返回 NULL，getDouble 返回 NaN，UI 端用 ?? 0 兜底
          correctRate: result.getDouble(result.getColumnIndex('correct_rate')),
        });
      }
    } finally {
      result.close();
    }
    return stats;
  }

  /** 各分类正确率（基于 question_stats） */
  async getCategoryStats(bankId?: number): Promise<CategoryStat[]> {
    let sql = `
      SELECT q.category,
             SUM(qs.attempt_count) AS attempt_count,
             SUM(qs.correct_count) AS correct_count
      FROM question_stats qs
      JOIN questions q ON q.id = qs.question_id
      WHERE q.category != ''`;
    const args: relationalStore.ValueType[] = [];
    if (bankId !== undefined) {
      sql += ` AND q.bank_id = ?`;
      args.push(bankId);
    }
    sql += ` GROUP BY q.category ORDER BY attempt_count DESC`;
    const result = await this.store.querySql(sql, args);
    const stats: CategoryStat[] = [];
    try {
      while (result.goToNextRow()) {
        const attempt = result.getLong(result.getColumnIndex('attempt_count'));
        const correct = result.getLong(result.getColumnIndex('correct_count'));
        stats.push({
          category:      result.getString(result.getColumnIndex('category')),
          attemptCount:  attempt,
          correctCount:  correct,
          correctRate:   attempt > 0 ? correct / attempt : 0,
        });
      }
    } finally {
      result.close();
    }
    return stats;
  }

  /** 综合统计。使用 COALESCE 兜底 SUM/AVG 在空表上返回的 NULL，
   *  使用加权正确率（SUM(correct)/SUM(total)）替代 AVG(每会话正确率)，
   *  避免会话题量差异大时小会话被过度放大 */
  async getOverall(): Promise<OverallStat> {
    const sql = `
      SELECT COUNT(*) AS total_sessions,
             COALESCE(SUM(total_count), 0) AS total_questions,
             COALESCE(
               SUM(CASE WHEN total_count > 0 THEN correct_count END) * 1.0
                 / NULLIF(SUM(total_count), 0),
             0) AS avg_correct_rate,
             COALESCE(SUM(duration_sec), 0) AS total_duration
      FROM practice_sessions
      WHERE status = 'completed'`;
    const result = await this.store.querySql(sql);
    try {
      if (result.goToFirstRow()) {
        return {
          totalSessions:     result.getLong(result.getColumnIndex('total_sessions')),
          totalQuestions:    result.getLong(result.getColumnIndex('total_questions')),
          avgCorrectRate:    result.getDouble(result.getColumnIndex('avg_correct_rate')),
          totalDurationSec:  result.getLong(result.getColumnIndex('total_duration')),
        };
      }
    } finally {
      result.close();
    }
    return { totalSessions: 0, totalQuestions: 0, avgCorrectRate: 0, totalDurationSec: 0 };
  }
}
