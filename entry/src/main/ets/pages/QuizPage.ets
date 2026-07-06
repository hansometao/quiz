import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { DatabaseService } from '../service/DatabaseService';
import { QuizEngine } from '../service/QuizEngine';
import { Question, PracticeConfig, PracticeMode, QuestionType, AnswerStatus, normalizePracticeConfig } from '../model/Models';
import { QuestionCard } from '../components/QuestionCard';
import { LoadingOverlay } from '../components/CommonComponents';
import { DateUtils } from '../utils/DateUtils';

@Entry
@Component
struct QuizPage {
  private bankId: number = (router.getParams() as Record<string, number> | null)?.['bankId'] ?? 0;
  // config 解析失败/字段缺失时统一走 normalizePracticeConfig 兜底，避免非法 JSON 或旧版备份导致 QuizEngine 崩溃
  private config: PracticeConfig = (() => {
    try {
      const raw = JSON.parse((router.getParams() as Record<string, string> | null)?.['config'] ?? '{}') as Partial<PracticeConfig>;
      return normalizePracticeConfig(raw);
    } catch {
      return normalizePracticeConfig(null);
    }
  })();

  @State questions: Question[] = [];
  @State currentIdx: number = 0;
  @State answers: Map<number, string> = new Map();
  @State submitted: Map<number, boolean> = new Map();
  @State sessionId: number = 0;
  @State loading: boolean = true;
  @State elapsed: number = 0;       // 已用时（秒）
  @State remaining: number = 0;     // 剩余时间（秒），0=不限时
  // 墙钟基准（毫秒），计时基于 Date.now() 差值，避免后台/卡顿时 setInterval 漏触导致漂移
  private startWallMs: number = 0;
  private questionStartTime: number = 0;
  private skippedIndices: number[] = [];
  private timer: number = -1;
  // 标记页面是否已销毁，所有 await 后必须检查，避免在销毁组件上写状态/启动定时器
  private isAlive: boolean = true;
  // 标记答题提交是否进行中，防止快速连点产生重复答题记录
  private submitting: boolean = false;
  // 标记完成练习是否进行中，防止限时到点与点击完成按钮双触发
  private isFinishing: boolean = false;

  aboutToAppear() {
    this.initQuiz();
  }

  aboutToDisappear() {
    this.isAlive = false;
    this.clearTimer();
  }

  // 页面隐藏（被路由覆盖/切后台）时暂停定时器，节省资源并配合墙钟在 onShow 时校正
  onPageHide() {
    this.clearTimer();
  }

  // 页面恢复可见时基于墙钟校正 elapsed/remaining 后重启定时器
  onPageShow() {
    if (this.sessionId > 0 && !this.loading && this.timer < 0) {
      this.syncElapsedFromWall();
      this.startTimer();
    }
  }

  async initQuiz() {
    try {
      const engine = new QuizEngine();
      this.questions = await engine.buildQuestionList(this.bankId, this.config);
      if (!this.isAlive) return;
      if (this.questions.length === 0) {
        // 题库为空或筛选无结果：提示并退出，避免后续 startTimer 在 0 题场景空转
        this.loading = false;
        promptAction.showToast({ message: '没有可练习的题目' });
        setTimeout(() => router.back(), 800);
        return;
      }
      const db = DatabaseService.getInstance();
      this.sessionId = await db.sessions.insert(this.bankId, this.config.mode, this.config, this.questions.length);
      if (!this.isAlive) return;
      this.loading = false;
      this.startWallMs = Date.now();
      this.questionStartTime = Date.now();
      if (this.config.timeLimitSec > 0) {
        this.remaining = this.config.timeLimitSec;
      }
      this.startTimer();
    } catch (e) {
      if (!this.isAlive) return;
      console.error('QuizPage initQuiz 失败', e);
      this.loading = false;
      promptAction.showToast({ message: '出题失败：' + (e as Error).message });
      setTimeout(() => router.back(), 1200);
    }
  }

  // 基于墙钟重算 elapsed 与 remaining，解决 setInterval 在后台被挂起导致的计时漂移
  private syncElapsedFromWall(): void {
    if (this.startWallMs === 0) return;
    this.elapsed = Math.floor((Date.now() - this.startWallMs) / 1000);
    if (this.config.timeLimitSec > 0) {
      this.remaining = Math.max(0, this.config.timeLimitSec - this.elapsed);
    }
  }

  private startTimer(): void {
    if (this.timer >= 0) return;
    this.timer = setInterval(() => {
      this.syncElapsedFromWall();
      if (this.config.timeLimitSec > 0 && this.remaining <= 0) {
        this.clearTimer();
        this.finishQuiz();
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
    // 防重入：快速连点确认按钮时，submitted 标志在 await 完成后才置位，
    // 此处同步占位避免插入重复答题记录
    if (this.submitting) return;
    if (this.submitted.get(this.currentIdx) ?? false) return;
    this.submitting = true;
    // 同步标记 submitted，UI 立即切换为"下一题"按钮，杜绝二次点击
    const preSubmitted = new Map(this.submitted);
    preSubmitted.set(this.currentIdx, true);
    this.submitted = preSubmitted;

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

    try {
      await db.sessions.insertAnswer(this.sessionId, q.id, userAns, isCorrect, timeMs);
      // 同步更新错题本（使用用户设置的阈值）
      if (isCorrect === AnswerStatus.WRONG) {
        await db.mistakes.upsert(q.id, q.bankId, userAns);
      } else if (isCorrect === AnswerStatus.CORRECT) {
        await db.mistakes.onCorrectAnswer(q.id, db.autoRemoveThreshold);
      }
    } catch (e) {
      // DB 写入失败：回滚 submitted 标志，让用户可重试
      console.error('QuizPage submit 失败', e);
      const rolledBack = new Map(this.submitted);
      rolledBack.set(this.currentIdx, false);
      this.submitted = rolledBack;
      promptAction.showToast({ message: '提交失败，请重试' });
    } finally {
      this.submitting = false;
    }
  }

  private async skip(): Promise<void> {
    if (!this.currentQuestion) return;
    if (this.skippedIndices.indexOf(this.currentIdx) < 0) {
      this.skippedIndices = [...this.skippedIndices, this.currentIdx];
    }
    // 必须等 DB 写入完成再 next/finish，否则最后一题跳过后立即完成可能丢失该记录
    try {
      await DatabaseService.getInstance().sessions.insertAnswer(
        this.sessionId, this.currentQuestion.id, '', AnswerStatus.SKIPPED, 0
      );
    } catch (e) {
      console.error('QuizPage skip 失败', e);
    }
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
    // 重入守卫：限时到点回调与点击完成按钮可能几乎同时触发
    if (this.isFinishing) return;
    this.isFinishing = true;
    this.clearTimer();
    try {
      // 基于墙钟最终校正 elapsed，保证 ResultPage 显示的用时与实际一致
      this.syncElapsedFromWall();
      const records = await DatabaseService.getInstance().sessions.getAnswersBySession(this.sessionId);
      if (!this.isAlive) return;
      const correct = records.filter(r => r.isCorrect === AnswerStatus.CORRECT).length;
      const score = records.reduce((sum, r) => sum + (r.isCorrect === AnswerStatus.CORRECT ? (r.question?.score ?? 1) : 0), 0);
      await DatabaseService.getInstance().sessions.finish(this.sessionId, correct, this.elapsed, score);
      if (!this.isAlive) return;
      router.replaceUrl({
        url: 'pages/ResultPage',
        params: { sessionId: this.sessionId }
      });
    } catch (e) {
      console.error('QuizPage finishQuiz 失败', e);
      this.isFinishing = false;
      promptAction.showToast({ message: '提交结果失败，请重试' });
    }
  }

  private async onExit(): Promise<void> {
    this.clearTimer();
    if (this.sessionId > 0) {
      try {
        // await abandon 完成再返回，避免会话残留 ongoing 状态
        await DatabaseService.getInstance().sessions.abandon(this.sessionId);
      } catch (e) {
        console.error('QuizPage onExit abandon 失败', e);
      }
    }
    router.back();
  }
}
