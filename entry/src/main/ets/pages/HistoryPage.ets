import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { PracticeSession } from '../model/Models';
import { QuizEngine } from '../service/QuizEngine';
import { EmptyState, LoadingOverlay } from '../components/CommonComponents';
import { DateUtils } from '../utils/DateUtils';

@Component
export struct HistoryPage {
  @State sessions: PracticeSession[] = [];
  @State loading: boolean = false;
  // 代际 token：避免快速切换 tab 时旧请求覆盖新数据
  private loadGen: number = 0;
  private isAlive: boolean = true;
  @StorageProp('tabTick') @Watch('onTabTick') private tabTick: number = 0;
  @StorageProp('activeTab') private activeTab: number = 0;

  aboutToAppear() { this.loadHistory(); }

  aboutToDisappear() {
    this.isAlive = false;
  }

  // Index 切换/回显时通过 AppStorage 通知刷新（@Component 子组件不接收 onPageShow）
  private onTabTick(): void {
    if (this.activeTab === 2) {
      this.loadHistory();
    }
  }

  async loadHistory() {
    const gen = ++this.loadGen;
    this.loading = true;
    try {
      await DatabaseService.getInstance().ready();
      const sessions = await DatabaseService.getInstance().sessions.getCompleted(100);
      if (!this.isAlive || gen !== this.loadGen) return;
      this.sessions = sessions;
    } catch (e) {
      if (!this.isAlive || gen !== this.loadGen) return;
      console.error('HistoryPage loadHistory 失败', e);
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
          Text('历史记录').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        }
        .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 12 })

        if (this.sessions.length === 0 && !this.loading) {
          EmptyState({
            icon: '📋',
            title: '还没有练习记录',
            subtitle: '完成练习后，记录会显示在这里',
            actionText: '',
          })
        } else {
          List({ space: 10 }) {
            ForEach(this.sessions, (s: PracticeSession) => {
              ListItem() {
                Column() {
                  Row() {
                    Text(s.bankName ?? '未知题库')
                      .fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.correctRateStr(s))
                      .fontSize(18).fontWeight(FontWeight.Bold)
                      .fontColor(this.rateColor(s))
                  }

                  Row() {
                    Text(QuizEngine.modeLabel(s.mode))
                      .fontSize(12).fontColor($r('app.color.primary'))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('#E8F2FF').borderRadius(4)
                    Text('  ' + s.totalCount + ' 题')
                      .fontSize(12).fontColor($r('app.color.text_secondary'))
                    Text('  用时 ' + DateUtils.formatDuration(s.durationSec))
                      .fontSize(12).fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(DateUtils.formatDate(s.startedAt))
                      .fontSize(12).fontColor($r('app.color.text_tertiary'))
                  }
                  .margin({ top: 8 })

                  // 正确/错误/跳过进度条可视化
                  Row() {
                    Stack() {
                      Progress({ value: s.correctCount, total: s.totalCount })
                        .width('100%').height(6)
                        .color($r('app.color.success')).backgroundColor($r('app.color.border'))
                    }
                    .layoutWeight(1)

                    Text(s.correctCount + '/' + s.totalCount)
                      .fontSize(12).fontColor($r('app.color.text_secondary')).margin({ left: 8 })
                  }
                  .margin({ top: 8 })
                }
                .padding(14).backgroundColor($r('app.color.bg_card')).borderRadius(12)
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/HistoryDetailPage',
                    params: { sessionId: s.id }
                  });
                })
              }
            }, (s: PracticeSession) => s.id.toString())
          }
          .layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: '' })
    }
  }

  private correctRateStr(s: PracticeSession): string {
    if (!s.totalCount) return '--%';
    return Math.round(s.correctCount / s.totalCount * 100) + '%';
  }

  private rateColor(s: PracticeSession): ResourceColor {
    const rate = s.totalCount ? s.correctCount / s.totalCount : 0;
    if (rate >= 0.8) return $r('app.color.success');
    if (rate >= 0.6) return $r('app.color.warning');
    return $r('app.color.danger');
  }
}
