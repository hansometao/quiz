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
    const sql = `
      SELECT date(s.finished_at, 'unixepoch', 'localtime') AS date,
             COUNT(*)                                       AS count,
             AVG(CASE WHEN s.total_count > 0
                      THEN CAST(s.correct_count AS REAL) / s.total_count END) AS correct_rate
      FROM practice_sessions s
      WHERE s.status = 'completed'
        AND s.finished_at >= strftime('%s', 'now', ? )
      GROUP BY date
      ORDER BY date ASC`;
    // SQLite strftime 相对时间：'now','-N days' -> 这里传 '-${days} days'
    const result = await this.store.querySql(sql, [`-${days} days`]);
    const stats: DailyStat[] = [];
    while (result.goToNextRow()) {
      stats.push({
        date:        result.getString(result.getColumnIndex('date')),
        count:       result.getLong(result.getColumnIndex('count')),
        correctRate: result.getDouble(result.getColumnIndex('correct_rate')),
      });
    }
    result.close();
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
    result.close();
    return stats;
  }

  /** 综合统计 */
  async getOverall(): Promise<OverallStat> {
    const sql = `
      SELECT COUNT(*) AS total_sessions,
             SUM(total_count) AS total_questions,
             AVG(CASE WHEN total_count > 0
                      THEN CAST(correct_count AS REAL) / total_count END) AS avg_correct_rate,
             SUM(duration_sec) AS total_duration
      FROM practice_sessions
      WHERE status = 'completed'`;
    const result = await this.store.querySql(sql);
    if (result.goToFirstRow()) {
      const stat: OverallStat = {
        totalSessions:     result.getLong(result.getColumnIndex('total_sessions')),
        totalQuestions:    result.getLong(result.getColumnIndex('total_questions')),
        avgCorrectRate:    result.getDouble(result.getColumnIndex('avg_correct_rate')),
        totalDurationSec:  result.getLong(result.getColumnIndex('total_duration')),
      };
      result.close();
      return stat;
    }
    result.close();
    return { totalSessions: 0, totalQuestions: 0, avgCorrectRate: 0, totalDurationSec: 0 };
  }
}
