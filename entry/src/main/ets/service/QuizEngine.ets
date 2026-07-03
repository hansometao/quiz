import { Question, PracticeConfig, PracticeMode, Difficulty, QuestionType } from '../model/Models';
import { DatabaseService } from './DatabaseService';

/**
 * 出题引擎 — 根据练习配置从数据库取题并排序
 */
export class QuizEngine {
  private db = DatabaseService.getInstance();

  /**
   * 根据配置生成题目列表
   */
  async buildQuestionList(bankId: number, config: PracticeConfig): Promise<Question[]> {
    let questions: Question[] = [];

    switch (config.mode) {
      case PracticeMode.MISTAKE:
        // 错题专练：从错题本取题（bankId=0 表示全题库错题）
        questions = await this.db.questions.getMistakesForPractice(bankId);
        break;
      default:
        // SEQUENTIAL/RANDOM/EXAM/CATEGORY/DIFFICULTY 均从题库取题；
        // CATEGORY 与 DIFFICULTY 模式靠 config.categories / config.difficulties 筛选，
        // 由 PracticeConfigPage 根据所选模式暴露对应筛选 UI。
        questions = await this.db.questions.getByBank(bankId, {
          types:        config.types.length        > 0 ? config.types        : undefined,
          categories:   config.categories.length   > 0 ? config.categories   : undefined,
          difficulties: config.difficulties.length > 0 ? config.difficulties : undefined,
        });
    }

    // 随机/模拟考试模式：打乱顺序
    if (config.mode === PracticeMode.RANDOM || config.mode === PracticeMode.EXAM) {
      questions = this.shuffle(questions);
    }

    // 截取指定题数
    if (config.totalCount > 0 && config.totalCount < questions.length) {
      questions = questions.slice(0, config.totalCount);
    }

    return questions;
  }

  /** Fisher-Yates 随机打乱 */
  private shuffle<T>(arr: T[]): T[] {
    const result = [...arr];
    for (let i = result.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [result[i], result[j]] = [result[j], result[i]];
    }
    return result;
  }

  /**
   * 判断用户答案是否正确
   * @returns true=正确, false=错误
   */
  checkAnswer(question: Question, userAnswer: string): boolean {
    const correct = question.answer.trim().toUpperCase();
    const user    = userAnswer.trim().toUpperCase();

    switch (question.type) {
      case QuestionType.SINGLE:
      case QuestionType.JUDGE:
        return correct === user;

      case QuestionType.MULTI: {
        // 多选：将字母排序后比较
        const sortLetters = (s: string) =>
          s.replace(/[,，\s]/g, '').split('').sort().join('');
        return sortLetters(correct) === sortLetters(user);
      }

      case QuestionType.FILL: {
        // 填空：关键词匹配（分号分隔，全部包含即正确）
        const keywords = correct.split(';').map(k => k.trim().toLowerCase()).filter(Boolean);
        if (keywords.length === 0) return false;
        const uLower = user.toLowerCase();
        return keywords.every(kw => uLower.includes(kw));
      }

      case QuestionType.ESSAY:
        // 简答题：不自动判断，标记为"待核"（用户自评）
        return false;

      default:
        return false;
    }
  }

  /**
   * 计算填空题得分（0~1）
   * 用于部分正确的给分场景
   */
  scoreFillAnswer(userAnswer: string, correctAnswer: string): number {
    const keywords = correctAnswer.split(';').map(k => k.trim().toLowerCase()).filter(Boolean);
    if (keywords.length === 0) return 0;
    const uLower = userAnswer.toLowerCase();
    const matched = keywords.filter(kw => uLower.includes(kw)).length;
    return matched / keywords.length;
  }

  /**
   * 获取难度显示文字
   */
  static difficultyLabel(d: Difficulty): string {
    switch (d) {
      case Difficulty.EASY:   return '简单';
      case Difficulty.MEDIUM: return '中等';
      case Difficulty.HARD:   return '困难';
      default: return '中等';
    }
  }

  /**
   * 获取题型显示文字
   */
  static typeLabel(t: QuestionType): string {
    switch (t) {
      case QuestionType.SINGLE: return '单选题';
      case QuestionType.MULTI:  return '多选题';
      case QuestionType.JUDGE:  return '判断题';
      case QuestionType.FILL:   return '填空题';
      case QuestionType.ESSAY:  return '简答题';
      default: return '单选题';
    }
  }

  /**
   * 获取练习模式显示文字
   */
  static modeLabel(m: PracticeMode): string {
    switch (m) {
      case PracticeMode.SEQUENTIAL: return '顺序练习';
      case PracticeMode.RANDOM:     return '随机练习';
      case PracticeMode.EXAM:       return '模拟考试';
      case PracticeMode.MISTAKE:    return '错题专练';
      case PracticeMode.CATEGORY:   return '分类练习';
      case PracticeMode.DIFFICULTY: return '难度练习';
      default: return '练习';
    }
  }
}
