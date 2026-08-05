import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { MistakeItem, PracticeMode, PracticeConfig } from '../model/Models';
import { QuizEngine } from '../service/QuizEngine';
import { EmptyState, LoadingOverlay } from '../components/CommonComponents';

@Component
export struct MistakePage {
  @State mistakes: MistakeItem[] = [];
  @State loading: boolean = false;
  @State threshold: number = 3;
  // 代际 token：避免快速切换 tab 时旧请求覆盖新数据
  private loadGen: number = 0;
  private isAlive: boolean = true;
  @StorageProp('tabTick') @Watch('onTabTick') private tabTick: number = 0;
  @StorageProp('activeTab') private activeTab: number = 0;

  aboutToAppear() { this.loadMistakes(); }

  aboutToDisappear() {
    this.isAlive = false;
  }

  // Index 切换/回显时通过 AppStorage 通知刷新（@Component 子组件不接收 onPageShow）
  private onTabTick(): void {
    if (this.activeTab === 1) {
      this.loadMistakes();
    }
  }

  async loadMistakes() {
    const gen = ++this.loadGen;
    this.loading = true;
    try {
      const db = DatabaseService.getInstance();
      await db.ready();
      this.threshold = db.autoRemoveThreshold;
      const mistakes = await db.mistakes.getWithQuestions();
      if (!this.isAlive || gen !== this.loadGen) return;
      this.mistakes = mistakes;
    } catch (e) {
      if (!this.isAlive || gen !== this.loadGen) return;
      console.error('MistakePage loadMistakes 失败', e);
    } finally {
      if (this.isAlive && gen === this.loadGen) {
        this.loading = false;
      }
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('错题本').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Blank()
          if (this.mistakes.length > 0) {
            Button('专项练习').height(36).fontSize(14).borderRadius(10)
              .backgroundColor($r('app.color.danger')).fontColor(Color.White)
              .onClick(() => this.startMistakePractice())
          }
        }
        .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 12 })

        if (this.mistakes.length === 0 && !this.loading) {
          EmptyState({
            icon: '🎯',
            title: '暂无错题',
            subtitle: '继续练习，答错的题会自动收录到这里',
            actionText: '',
          })
        } else {
          // 统计信息
          Row() {
            Text(`共 ${this.mistakes.length} 道错题`)
              .fontSize(14).fontColor($r('app.color.text_secondary'))
          }
          .padding({ left: 16, bottom: 8 })
          .alignSelf(ItemAlign.Start)

          List({ space: 10 }) {
            ForEach(this.mistakes, (m: MistakeItem) => {
              ListItem() {
                Column() {
                  Row() {
                    if (m.question) {
                      Text(QuizEngine.typeLabel(m.question.type))
                        .fontSize(11).fontColor($r('app.color.primary'))
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor('#E8F2FF').borderRadius(4)
                      if (m.question.category) {
                        Text(m.question.category)
                          .fontSize(11).fontColor($r('app.color.text_secondary'))
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .backgroundColor($r('app.color.bg_primary')).borderRadius(4)
                          .margin({ left: 6 })
                      }
                    }
                    Blank()
                    Text(`答错 ${m.wrongCount} 次`)
                      .fontSize(11).fontColor($r('app.color.danger'))
                  }
                  .margin({ bottom: 8 })

                  Text(m.question?.question ?? '')
                    .fontSize(14).fontColor($r('app.color.text_primary'))
                    .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(20)

                  Row() {
                    Text('正确答案：' + (m.question?.answer ?? ''))
                      .fontSize(12).fontColor($r('app.color.success'))
                    if (m.myLastAnswer) {
                      Text('  我的答案：' + m.myLastAnswer)
                        .fontSize(12).fontColor($r('app.color.danger'))
                    }
                  }
                  .margin({ top: 8 })

                  // 连续正确进度条（threshold 至少为 1，避免 total:0 触发除零异常）
                  if (m.consecutiveCorrect > 0) {
                    Row() {
                      Text('连续正确：' + m.consecutiveCorrect + '/' + this.threshold)
                        .fontSize(11).fontColor($r('app.color.text_secondary'))
                      Progress({ value: m.consecutiveCorrect, total: Math.max(this.threshold, 1) })
                        .width(60).height(4)
                        .color($r('app.color.success')).backgroundColor($r('app.color.border'))
                        .margin({ left: 8 })
                    }
                    .margin({ top: 6 })
                  }
                }
                .padding(14).backgroundColor($r('app.color.bg_card')).borderRadius(12)
                .border({ width: 1, color: $r('app.color.border') })
              }
            }, (m: MistakeItem) => m.questionId.toString())
          }
          .layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: '' })
    }
  }

  private startMistakePractice(): void {
    if (this.mistakes.length === 0) return;
    // 错题专练：传 0 表示全题库错题，QuizEngine.questions.getMistakesForPractice 会取所有题库的错题
    const bankId = 0;
    const config: PracticeConfig = {
      mode: PracticeMode.MISTAKE,
      totalCount: Math.min(20, this.mistakes.length),
      types: [], categories: [], difficulties: [],
      timeLimitSec: 0, showExplanation: true, allowSkip: true,
    };
    router.pushUrl({ url: 'pages/QuizPage', params: { bankId, config: JSON.stringify(config) } });
  }
}
