/**
 * 题型枚举
 */
export enum QuestionType {
  SINGLE = 'single',   // 单选题
  MULTI  = 'multi',    // 多选题
  JUDGE  = 'judge',    // 判断题
  FILL   = 'fill',     // 填空题
  ESSAY  = 'essay',    // 简答题
}

/**
 * 难度枚举
 */
export enum Difficulty {
  EASY   = 1,
  MEDIUM = 2,
  HARD   = 3,
}

/**
 * 题库模型
 */
export interface QuestionBank {
  id: number;
  name: string;
  description: string;
  fileName: string;
  totalCount: number;
  createdAt: number;
  updatedAt: number;
  // 运行时统计（JOIN 查询填充）
  practiceCount?: number;
  avgCorrectRate?: number;
  lastPracticeAt?: number;
}

/**
 * 题目模型
 */
export interface Question {
  id: number;
  bankId: number;
  seqNo: number;
  type: QuestionType;
  question: string;
  optionA: string;
  optionB: string;
  optionC: string;
  optionD: string;
  optionE: string;
  answer: string;
  explanation: string;
  category: string;
  difficulty: Difficulty;
  score: number;
  isStarred: boolean;
  isFlagged: boolean;
  userNote: string;
  createdAt: number;
  // 运行时统计（JOIN 查询填充）
  attemptCount?: number;
  correctCount?: number;
  lastAnswered?: number;
}

/**
 * 练习模式枚举
 */
export enum PracticeMode {
  SEQUENTIAL = 'sequential', // 顺序练习
  RANDOM     = 'random',     // 随机练习
  EXAM       = 'exam',       // 模拟考试
  MISTAKE    = 'mistake',    // 错题专练
  CATEGORY   = 'category',   // 分类练习
  DIFFICULTY = 'difficulty', // 难度练习
}

/**
 * 练习配置（存入 config_json）
 * 数组字段标注为可选仅用于反序列化容错：从 JSON 解析或旧版备份还原时，
 * 这些字段可能缺失，统一通过 normalizePracticeConfig 补齐为空数组后使用。
 */
export interface PracticeConfig {
  mode: PracticeMode;
  totalCount: number;
  types?: QuestionType[];        // 指定题型，空=全部
  categories?: string[];         // 指定分类，空=全部
  difficulties?: Difficulty[];   // 指定难度，空=全部
  timeLimitSec: number;         // 0=不限时
  showExplanation: boolean;     // 答题后是否显示解析
  allowSkip: boolean;           // 是否允许跳题
}

/** 默认练习配置（兼容旧版备份/非法 JSON 反序列化场景） */
export const DEFAULT_PRACTICE_CONFIG: PracticeConfig = {
  mode: PracticeMode.RANDOM,
  totalCount: 0,
  types: [],
  categories: [],
  difficulties: [],
  timeLimitSec: 0,
  showExplanation: true,
  allowSkip: true,
};

/**
 * 规范化练习配置：补齐可选数组字段为空数组，标量字段兜底默认值，
 * 防止旧版备份/非法 JSON 导致 QuizEngine 访问 undefined.length 崩溃。
 */
export function normalizePracticeConfig(raw?: Partial<PracticeConfig> | null): PracticeConfig {
  if (!raw) return { ...DEFAULT_PRACTICE_CONFIG };
  return {
    mode:            raw.mode            ?? DEFAULT_PRACTICE_CONFIG.mode,
    totalCount:      raw.totalCount      ?? DEFAULT_PRACTICE_CONFIG.totalCount,
    types:           Array.isArray(raw.types)           ? raw.types           : [],
    categories:      Array.isArray(raw.categories)      ? raw.categories      : [],
    difficulties:    Array.isArray(raw.difficulties)    ? raw.difficulties    : [],
    timeLimitSec:    raw.timeLimitSec    ?? DEFAULT_PRACTICE_CONFIG.timeLimitSec,
    showExplanation: raw.showExplanation ?? DEFAULT_PRACTICE_CONFIG.showExplanation,
    allowSkip:       raw.allowSkip       ?? DEFAULT_PRACTICE_CONFIG.allowSkip,
  };
}

/**
 * 练习会话状态枚举
 */
export enum SessionStatus {
  ONGOING   = 'ongoing',
  COMPLETED = 'completed',
  ABANDONED = 'abandoned',
}

/**
 * 练习会话模型
 */
export interface PracticeSession {
  id: number;
  bankId: number;
  mode: PracticeMode;
  configJson: string;
  totalCount: number;
  correctCount: number;
  durationSec: number;
  totalScore: number;
  status: SessionStatus;
  startedAt: number;
  finishedAt: number;
  // 运行时填充
  bankName?: string;
  config?: PracticeConfig;
}

/**
 * 答案状态枚举
 */
export enum AnswerStatus {
  WRONG   = 0,
  CORRECT = 1,
  SKIPPED = 2,
}

/**
 * 答题记录模型
 */
export interface AnswerRecord {
  id: number;
  sessionId: number;
  questionId: number;
  userAnswer: string;
  isCorrect: AnswerStatus;
  timeSpentMs: number;
  answeredAt: number;
  // 运行时填充
  question?: Question;
}

/** 填空题评分回调类型 */
export type FillScoreCallback = (userAnswer: string, correctAnswer: string) => number;

/**
 * 题目统计缓存
 */
export interface QuestionStat {
  questionId: number;
  attemptCount: number;
  correctCount: number;
  lastAnswered: number;
  updatedAt: number;
}

/**
 * 答题结果汇总（用于结果页）
 */
export interface QuizResult {
  session: PracticeSession;
  correctCount: number;
  wrongCount: number;
  skippedCount: number;
  correctRate: number;
  durationSec: number;
  totalScore: number;
  wrongRecords: AnswerRecord[];
}

/**
 * 错题记录（mistakes 表，记录每道题的错误历史）
 * lastPracticeTime / addedAt 为 Unix 时间戳（秒），与 DB 列类型一致，
 * 与项目其他模型（Question.createdAt、PracticeSession.startedAt）保持统一
 */
export interface MistakeItem {
  questionId: number;
  bankId: number;
  wrongCount: number;            // 累计答错次数
  consecutiveCorrect: number;    // 连续答对次数（用于自动移出错题本）
  myLastAnswer?: string;         // 最近一次的错误答案
  lastPracticeTime?: number;     // 最近练习时间（Unix 秒）
  addedAt?: number;              // 加入错题本时间（Unix 秒）
  // 运行时填充
  question?: Question;
}
