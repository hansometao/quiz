/**
 * QuestionRepository.ets
 * 题目表（questions）数据访问层
 */
import relationalStore from '@ohos.data.relationalStore';
import { Question, QuestionType, Difficulty } from '../../model/Models';

export interface QuestionQueryOptions {
  types?: QuestionType[];
  categories?: string[];
  difficulties?: Difficulty[];
  limit?: number;
  offset?: number;
}

export class QuestionRepository {
  constructor(private store: relationalStore.RdbStore) {}

  /** 批量插入题目（事务 + batchInsert 提升性能） */
  async batchInsert(bankId: number, questions: Partial<Question>[]): Promise<void> {
    if (questions.length === 0) return;
    const now = Math.floor(Date.now() / 1000);
    await this.store.beginTransaction();
    try {
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
        await this.store.insert('questions', values);
      }
      await this.store.commit();
    } catch (err) {
      await this.store.rollBack();
      throw err;
    }
  }

  /** 查询题库下所有题目（支持筛选 + 分页） */
  async getByBank(bankId: number, options?: QuestionQueryOptions): Promise<Question[]> {
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
    if (options?.limit !== undefined && options.limit > 0) {
      sql += ` LIMIT ? OFFSET ?`;
      args.push(options.limit, Math.max(0, options.offset ?? 0));
    }

    const result = await this.store.querySql(sql, args);
    const questions: Question[] = [];
    try {
      while (result.goToNextRow()) {
        questions.push(this.rowToQuestion(result));
      }
    } finally {
      result.close();
    }
    return questions;
  }

  /** 查询错题专练用题目（从 mistakes 表取，含练习进度） */
  async getMistakesForPractice(bankId?: number, options?: QuestionQueryOptions): Promise<Question[]> {
    let sql = `
      SELECT q.*, qs.attempt_count, qs.correct_count, qs.last_answered
      FROM mistakes m
      JOIN questions q ON q.id = m.question_id
      LEFT JOIN question_stats qs ON qs.question_id = q.id`;
    const args: relationalStore.ValueType[] = [];
    // bankId 为 0 或 undefined 时表示全题库错题
    if (bankId !== undefined && bankId > 0) {
      sql += ` WHERE m.bank_id = ?`;
      args.push(bankId);
    }
    // 支持类型/分类/难度筛选（与 getByBank 一致），修复 MISTAKE 模式忽略 config 筛选的问题
    if (options?.types && options.types.length > 0) {
      sql += (args.length > 0 ? ` AND` : ` WHERE`) + ` q.type IN (${options.types.map(() => '?').join(',')})`;
      args.push(...options.types);
    }
    if (options?.categories && options.categories.length > 0) {
      sql += (args.length > 0 ? ` AND` : ` WHERE`) + ` q.category IN (${options.categories.map(() => '?').join(',')})`;
      args.push(...options.categories);
    }
    if (options?.difficulties && options.difficulties.length > 0) {
      sql += (args.length > 0 ? ` AND` : ` WHERE`) + ` q.difficulty IN (${options.difficulties.map(() => '?').join(',')})`;
      args.push(...options.difficulties);
    }
    sql += ` ORDER BY m.updated_at DESC`;

    const result = await this.store.querySql(sql, args);
    const questions: Question[] = [];
    try {
      while (result.goToNextRow()) {
        questions.push(this.rowToQuestion(result));
      }
    } finally {
      result.close();
    }
    return questions;
  }

  async getCategories(bankId: number): Promise<string[]> {
    const sql = `SELECT DISTINCT category FROM questions WHERE bank_id = ? AND category != '' ORDER BY category`;
    const result = await this.store.querySql(sql, [bankId]);
    const cats: string[] = [];
    try {
      while (result.goToNextRow()) {
        cats.push(result.getString(0));
      }
    } finally {
      result.close();
    }
    return cats;
  }

  async deleteById(id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('questions');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  async updateMeta(id: number, data: { isStarred?: boolean; isFlagged?: boolean; userNote?: string }): Promise<void> {
    const values: relationalStore.ValuesBucket = {};
    if (data.isStarred !== undefined) values['is_starred'] = data.isStarred ? 1 : 0;
    if (data.isFlagged !== undefined) values['is_flagged'] = data.isFlagged ? 1 : 0;
    if (data.userNote  !== undefined) values['user_note']  = data.userNote;
    const predicates = new relationalStore.RdbPredicates('questions');
    predicates.equalTo('id', id);
    await this.store.update(values, predicates);
  }

  async getByIds(ids: number[]): Promise<Question[]> {
    if (!ids || ids.length === 0) return [];
    const placeholders = ids.map(() => '?').join(',');
    const sql = `SELECT * FROM questions WHERE id IN (${placeholders})`;
    const result = await this.store.querySql(sql, ids);
    const questions: Question[] = [];
    try {
      while (result.goToNextRow()) {
        questions.push(this.rowToQuestion(result));
      }
    } finally {
      result.close();
    }
    return questions;
  }

  async getById(id: number): Promise<Question | null> {
    const predicates = new relationalStore.RdbPredicates('questions');
    predicates.equalTo('id', id);
    const result = await this.store.query(predicates);
    try {
      if (result.goToFirstRow()) {
        return this.rowToQuestion(result);
      }
    } finally {
      result.close();
    }
    return null;
  }

  /** 供 SessionRepository.getAnswersBySession 使用：从已含题目字段的 ResultSet 解析 Question */
  rowToQuestion(result: relationalStore.ResultSet): Question {
    return {
      id:           this.getLong(result, 'id'),
      bankId:       this.getLong(result, 'bank_id'),
      seqNo:        this.getLong(result, 'seq_no'),
      type:         this.getString(result, 'type') as QuestionType,
      question:     this.getString(result, 'question'),
      optionA:      this.getString(result, 'option_a'),
      optionB:      this.getString(result, 'option_b'),
      optionC:      this.getString(result, 'option_c'),
      optionD:      this.getString(result, 'option_d'),
      optionE:      this.getString(result, 'option_e'),
      answer:       this.getString(result, 'answer'),
      explanation:  this.getString(result, 'explanation'),
      category:     this.getString(result, 'category'),
      difficulty:   this.getLong(result, 'difficulty') as Difficulty,
      score:        this.getDouble(result, 'score'),
      isStarred:    this.getLong(result, 'is_starred') === 1,
      isFlagged:    this.getLong(result, 'is_flagged') === 1,
      userNote:     this.getString(result, 'user_note'),
      createdAt:    this.getLong(result, 'created_at'),
      attemptCount: this.getLong(result, 'attempt_count'),
      correctCount: this.getLong(result, 'correct_count'),
      lastAnswered: this.getLong(result, 'last_answered'),
    };
  }

  // 列可能不存在（JOIN 子集场景），getColumnIndex 返回 -1 时给默认值，避免 getLong(-1) 行为未定义
  private getLong(result: relationalStore.ResultSet, col: string): number {
    const idx = result.getColumnIndex(col);
    return idx >= 0 ? result.getLong(idx) : 0;
  }
  private getString(result: relationalStore.ResultSet, col: string): string {
    const idx = result.getColumnIndex(col);
    return idx >= 0 ? result.getString(idx) : '';
  }
  private getDouble(result: relationalStore.ResultSet, col: string): number {
    const idx = result.getColumnIndex(col);
    return idx >= 0 ? result.getDouble(idx) : 0;
  }
}
