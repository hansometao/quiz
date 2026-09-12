import { describe, it, expect } from 'vitest';
import { QuizEngine } from '../entry/src/main/ets/service/QuizEngine';
import { Question, QuestionType, Difficulty, PracticeMode } from '../entry/src/main/ets/model/Models';

function q(type: QuestionType, answer: string): Question {
  return {
    id: 1, bankId: 1, seqNo: 1, type, question: 'Q',
    optionA: 'A', optionB: 'B', optionC: 'C', optionD: 'D',
    answer, explanation: '', category: '', difficulty: Difficulty.EASY,
    score: 1.0, isStarred: false, isFlagged: false, userNote: '',
  } as Question;
}

describe('QuizEngine.checkAnswer', () => {
  it('单选：全等比较（大小写/空格归一）', () => {
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.SINGLE, 'A'), 'a')).toBe(true);
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.SINGLE, 'A'), ' B ')).toBe(false);
  });

  it('判断：全等比较', () => {
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.JUDGE, '正确'), '正确')).toBe(true);
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.JUDGE, '正确'), '错误')).toBe(false);
  });

  it('多选：分隔符与顺序无关（B,A,D ≡ ABD）', () => {
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.MULTI, 'ABD'), 'B,A,D')).toBe(true);
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.MULTI, 'ABD'), 'A、B、D')).toBe(true);
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.MULTI, 'ABD'), 'AB')).toBe(false);
  });

  it('填空：分号分隔关键词须全部包含（大小写不敏感）', () => {
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.FILL, 'React;Hook'), 'react 的 hook')).toBe(true);
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.FILL, 'React;Hook'), 'react')).toBe(false);
  });

  it('填空：答案无关键词时判错（不崩溃）', () => {
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.FILL, '；；'), '任意')).toBe(false);
  });

  it('简答：不自动判分（恒 false）', () => {
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.ESSAY, '参考答案'), '参考答案')).toBe(false);
  });

  it('防御：userAnswer 为 undefined/null 不崩溃', () => {
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.SINGLE, 'A'), undefined as unknown as string)).toBe(false);
    expect(QuizEngine.prototype.checkAnswer(q(QuestionType.SINGLE, 'A'), null as unknown as string)).toBe(false);
  });
});

describe('QuizEngine 标签', () => {
  it('难度/题型/模式中文标签', () => {
    expect(QuizEngine.difficultyLabel(Difficulty.EASY)).toBe('简单');
    expect(QuizEngine.typeLabel(QuestionType.MULTI)).toBe('多选题');
    expect(QuizEngine.modeLabel(PracticeMode.MISTAKE)).toBe('错题专练');
  });
});
