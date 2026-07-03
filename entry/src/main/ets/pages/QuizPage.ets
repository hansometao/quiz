import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { QuizEngine } from '../service/QuizEngine';
import { Question, PracticeConfig, PracticeMode, QuestionType, AnswerStatus } from '../model/Models';
import { QuestionCard } from '../components/QuestionCard';
import { LoadingOverlay } from '../components/CommonComponents';
import { DateUtils } from '../utils/DateUtils';

@Entry
@Component
struct QuizPage {
  private bankId: number = (router.getParams() as Record<string, number> | null)?.['bankId'] ?? 0;
  private config: PracticeConfig = JSON.parse((router.getParams() as Record<string, string> | null)?.['config'] ?? '{}');

  @State questions: Question[] = [];
  @State currentIdx: number = 0;
  @State answers: Map<number, string> = new Map();
  @State submitted: Map<number, boolean> = new Map();
  @State sessionId: number = 0;
  @State loading: boolean = true;
  @State elapsed: number = 0;       // 已用时（秒）
  @State remaining: number = 0;     // 剩余时间（秒），0=不限时
  @State startTime: number = 0;
  @State questionStartTime: number = 0;
  @State skippedIndices: number[] = [];
  private timer: number = -1;

  aboutToAppear() {
    this.initQuiz();
  }

  aboutToDisappear() {
    this.clearTimer();
  }

  async initQuiz() {
    const engine = new QuizEngine();
    this.questions = await engine.buildQuestionList(this.bankId, this.config);
    const db = DatabaseService.getInstance();
    this.sessionId = await db.sessions.insert(this.bankId, this.config.mode, this.config, this.questions.length);
    this.loading = false;
    this.startTime = DateUtils.now();
    this.questionStartTime = Date.now();
    if (this.config.timeLimitSec > 0) {
      this.remaining = this.config.timeLimitSec;
    }
    this.startTimer();
  }

  private startTimer(): void {
    this.timer = setInterval(() => {
      this.elapsed++;
      if (this.config.timeLimitSec > 0) {
        this.remaining = Math.max(0, this.config.timeLimitSec - this.elapsed);
        if (this.remaining === 0) {
          this.clearTimer();
          this.finishQuiz();
        }
      }
    }, 1000);
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  get currentQuestion(): Question | undefined {
    return this.questions[this.currentIdx];
  }

  get isSubmitted(): boolean {
    return this.submitted.get(this.currentIdx) ?? false;
  }

  get currentAnswer(): string {
    return this.answers.get(this.currentIdx) ?? '';
  }

  build() {
    Stack() {
      Column() {
        // 导航栏
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('✕').fontSize(16).fontColor($r('app.color.text_secondary'))
          }
          .width(36).height(36).backgroundColor(Color.Transparent)
          .onClick(() => this.onExit())

          Blank()

          // 进度
          Text(`${this.currentIdx + 1} / ${this.questions.length}`)
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))

          Blank()

          // 计时器
          if (this.config.timeLimitSec > 0) {
            Text(DateUtils.formatDuration(this.remaining))
              .fontSize(15).fontColor(this.remaining < 60 ? $r('app.color.danger') : $r('app.color.text_secondary'))
          } else {
            Text(DateUtils.formatDuration(this.elapsed))
              .fontSize(14).fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

        // 进度条
        Progress({ value: this.currentIdx, total: this.questions.length })
          .width('100%').height(4)
          .color($r('app.color.primary')).backgroundColor($r('app.color.border'))

        // 题目内容
        Scroll() {
          Column() {
            if (this.currentQuestion) {
              QuestionCard({
                question: this.currentQuestion,
                selectedAnswer: this.currentAnswer,
                submitted: this.isSubmitted,
                onAnswerChange: (ans: string) => {
                  const newMap = new Map(this.answers);
                  newMap.set(this.currentIdx, ans);
                  this.answers = newMap;
                }
              })
            }
            Blank().height(100)
          }
          .padding(16)
        }
        .layoutWeight(1)

        // 底部操作栏
        Row() {
          // 上一题
          if (this.currentIdx > 0) {
            Button('上一题')
              .layoutWeight(1).height(48).fontSize(15).borderRadius(12)
              .backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
              .border({ width: 1, color: $r('app.color.primary') })
              .onClick(() => this.prev())
          }

          if (this.currentIdx > 0) Blank().width(10)

          // 中间按钮（跳过/确认/下一题）
          if (!this.isSubmitted) {
            if (this.config.allowSkip) {
              Button('跳 过')
                .layoutWeight(1).height(48).fontSize(15).borderRadius(12)
                .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary'))
                .border({ width: 1, color: $r('app.color.border') })
                .onClick(() => this.skip())
              Blank().width(10)
            }
            Button('确认答案')
              .layoutWeight(2).height(48).fontSize(15).borderRadius(12)
              .backgroundColor(this.currentAnswer ? $r('app.color.primary') : $r('app.color.border'))
              .fontColor(Color.White)
              .enabled(!!this.currentAnswer || this.currentQuestion?.type === QuestionType.ESSAY)
              .onClick(() => this.submit())
          } else {
            // 已提交：显示下一题或完成
            if (this.currentIdx < this.questions.length - 1) {
              Button('下一题 →')
                .layoutWeight(1).height(48).fontSize(15).borderRadius(12)
                .backgroundColor($r('app.color.primary')).fontColor(Color.White)
                .onClick(() => this.next())
            } else {
              Button('🎉 完成练习')
                .layoutWeight(1).height(48).fontSize(15).borderRadius(12)
                .backgroundColor($r('app.color.success')).fontColor(Color.White)
                .onClick(() => this.finishQuiz())
            }
          }
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 20, top: 10 })
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: '出题中...' })
    }
  }

  private async submit(): Promise<void> {
    if (this.sessionId === 0) return;
    if (!this.currentQuestion) return;
    if (this.skippedIndices.indexOf(this.currentIdx) >= 0) return;
    const q = this.currentQuestion;
    const userAns = this.currentAnswer || '';
    const timeMs = Date.now() - this.questionStartTime;
    const db = DatabaseService.getInstance();

    const engine = new QuizEngine();
    let isCorrect: AnswerStatus;
    if (q.type === QuestionType.ESSAY) {
      isCorrect = AnswerStatus.SKIPPED; // 简答题：标记为待核，不进入错题本，也不触发连续正确计数
    } else {
      isCorrect = engine.checkAnswer(q, userAns) ? AnswerStatus.CORRECT : AnswerStatus.WRONG;
    }

    await db.sessions.insertAnswer(this.sessionId, q.id, userAns, isCorrect, timeMs);

    // 同步更新错题本（使用用户设置的阈值）
    if (isCorrect === AnswerStatus.WRONG) {
      await db.mistakes.upsert(q.id, q.bankId, userAns);
    } else if (isCorrect === AnswerStatus.CORRECT) {
      await db.mistakes.onCorrectAnswer(q.id, db.autoRemoveThreshold);
    }

    const newSubmitted = new Map(this.submitted);
    newSubmitted.set(this.currentIdx, true);
    this.submitted = newSubmitted;
  }

  private skip(): void {
    if (!this.currentQuestion) return;
    // 记录为跳过：不再用魔术字符串污染 answers，改用 skippedIndices 标记
    if (this.skippedIndices.indexOf(this.currentIdx) < 0) {
      this.skippedIndices = [...this.skippedIndices, this.currentIdx];
    }
    DatabaseService.getInstance().sessions.insertAnswer(
      this.sessionId, this.currentQuestion.id, '', AnswerStatus.SKIPPED, 0
    );
    const newSubmitted = new Map(this.submitted);
    newSubmitted.set(this.currentIdx, true);
    this.submitted = newSubmitted;
    this.next();
  }

  private next(): void {
    if (this.currentIdx < this.questions.length - 1) {
      this.currentIdx++;
      this.questionStartTime = Date.now();
    }
  }

  private prev(): void {
    if (this.currentIdx > 0) {
      this.currentIdx--;
    }
  }

  private async finishQuiz(): Promise<void> {
    this.clearTimer();
    const records = await DatabaseService.getInstance().sessions.getAnswersBySession(this.sessionId);
    const correct = records.filter(r => r.isCorrect === AnswerStatus.CORRECT).length;
    const score = records.reduce((sum, r) => sum + (r.isCorrect === AnswerStatus.CORRECT ? (r.question?.score ?? 1) : 0), 0);
    await DatabaseService.getInstance().sessions.finish(this.sessionId, correct, this.elapsed, score);

    router.replaceUrl({
      url: 'pages/ResultPage',
      params: { sessionId: this.sessionId }
    });
  }

  private onExit(): void {
    this.clearTimer();
    DatabaseService.getInstance().sessions.abandon(this.sessionId);
    router.back();
  }
}
