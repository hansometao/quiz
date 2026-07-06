/**
 * BankRepository.ets
 * 题库表（question_banks）数据访问层
 */
import relationalStore from '@ohos.data.relationalStore';
import { QuestionBank } from '../../model/Models';

export class BankRepository {
  constructor(private store: relationalStore.RdbStore) {}

  /** 插入题库，返回新 ID */
  async insert(name: string, description: string, fileName: string): Promise<number> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = {
      name, description, file_name: fileName,
      total_count: 0, created_at: now, updated_at: now,
    };
    return await this.store.insert('question_banks', values);
  }

  /** 查询所有题库（含统计）。COALESCE 兜底无会话题库的 AVG/MAX 返回 NULL，
   *  使用加权正确率替代 AVG(每会话正确率) */
  async getAll(): Promise<QuestionBank[]> {
    const sql = `
      SELECT b.*,
             COUNT(DISTINCT s.id)                                   AS practice_count,
             COALESCE(
               SUM(CASE WHEN s.total_count > 0 THEN s.correct_count END) * 1.0
                 / NULLIF(SUM(s.total_count), 0),
             0)                                                     AS avg_correct_rate,
             COALESCE(MAX(s.started_at), 0)                         AS last_practice_at
      FROM question_banks b
      LEFT JOIN practice_sessions s ON s.bank_id = b.id AND s.status = 'completed'
      GROUP BY b.id
      ORDER BY b.updated_at DESC`;
    const result = await this.store.querySql(sql);
    const banks: QuestionBank[] = [];
    try {
      while (result.goToNextRow()) {
        banks.push(this.rowToBank(result));
      }
    } finally {
      result.close();
    }
    return banks;
  }

  async getById(id: number): Promise<QuestionBank | null> {
    const predicates = new relationalStore.RdbPredicates('question_banks');
    predicates.equalTo('id', id);
    const result = await this.store.query(predicates);
    try {
      if (result.goToFirstRow()) {
        return this.rowToBank(result);
      }
    } finally {
      result.close();
    }
    return null;
  }

  async update(id: number, name: string, description: string): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const values: relationalStore.ValuesBucket = { name, description, updated_at: now };
    const predicates = new relationalStore.RdbPredicates('question_banks');
    predicates.equalTo('id', id);
    await this.store.update(values, predicates);
  }

  async delete(id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('question_banks');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  /** 同步题库题目数量 */
  async refreshCount(bankId: number): Promise<void> {
    await this.store.executeSql(
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
}
