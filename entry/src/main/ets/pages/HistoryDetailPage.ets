/**
 * HistoryDetailPage.ets
 * 历史练习详情页
 *   - 展示单次练习的全部答题记录
 *   - 正确/错误高亮
 *   - 可查看每题解析
 */

import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { AnswerRecord, PracticeSession, AnswerStatus, PracticeMode, SessionStatus } from '../model/Models';
import { QuizEngine } from '../service/QuizEngine';
import { EmptyState, LoadingOverlay } from '../components/CommonComponents';
import { DateUtils } from '../utils/DateUtils';

@Entry
@Component
struct HistoryDetailPage {
  private sessionId: number = (router.getParams() as Record<string, number> | null)?.['sessionId'] ?? 0;

  @State session: PracticeSession | null = null;
  @State records: AnswerRecord[] = [];
  @State loading: boolean = true;
  @State expandedId: number = -1;  // 当前展开解析的记录 ID

  aboutToAppear() { this.loadData(); }

  async loadData() {
    this.loading = true;
    const db = DatabaseService.getInstance();
    // 同时查 session 和所有答题记录（含题目信息）
    const [sessions, records] = await Promise.all([
      db.sessions.getCompleted(200),
      db.sessions.getAnswersBySession(this.sessionId),
    ]);
    this.records = records;
    // 从已查到的 sessions 中找到对应 session
    const found = sessions.find(s => s.id === this.sessionId);
    if (found) {
      this.session = found;
    } else {
      // getCompleted 仅返回 completed 状态的 session，尝试用 getById（不限制 status）单独查询
      const direct = await db.sessions.getById(this.sessionId);
      if (direct) {
        this.session = direct;
      } else if (records.length > 0) {
        // 兜底：session 记录缺失，手动组装
        const correctCnt = records.filter(r => r.isCorrect === AnswerStatus.CORRECT).length;
        // 时长用首末答题时间差（与 ResultPage.calcDuration 算法保持一致）
        const times = records.map(r => r.answeredAt);
        const first = Math.min(...times);
        const last  = Math.max(...times);
        this.session = {
          id:           this.sessionId,
          bankId:       0,
          mode:         'sequential' as PracticeMode,
          configJson:   '{}',
          totalCount:   records.length,
          correctCount: correctCnt,
          durationSec:  last - first,  // 单条记录时 first === last，结果为 0
          totalScore:   0,
          status:       'completed' as SessionStatus,
          startedAt:    first,
          finishedAt:   last,
        } as PracticeSession;
      }
    }
    this.loading = false;
  }

  build() {
    Stack() {
      Column() {
        // ── 导航栏 ──
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('←').fontSize(18).fontColor($r('app.color.text_primary'))
          }
          .width(36).height(36).backgroundColor(Color.Transparent).onClick(() => router.back())

          Text('练习详情').fontSize(18).fontWeight(FontWeight.Bold).margin({ left: 8 })
          Blank()
        }
        .width('100%').padding(16)

        // ── 汇总卡 ──
        if (this.session) {
          Row() {
            this.SummaryItem('题目数', String(this.session.totalCount))
            this.SummaryItem('正确', String(this.session.correctCount), '#34C759')
            this.SummaryItem('错误', String(this.session.totalCount - this.session.correctCount), '#FF3B30')
            this.SummaryItem('正确率', this.rateStr(this.session), this.rateColor(this.session))
          }
          .width('100%').padding({ left: 16, right: 16, bottom: 12 })
          .justifyContent(FlexAlign.SpaceBetween)
        }

        // ── 答题记录列表 ──
        if (this.records.length === 0 && !this.loading) {
          EmptyState({ icon: '📋', title: '暂无答题记录', subtitle: '还没有任何答题记录，快去练习吧！', actionText: '' })
        } else {
          List({ space: 10 }) {
            ForEach(this.records, (r: AnswerRecord, idx: number) => {
              ListItem() {
                Column() {
                  Row() {
                    // 序号 + 对错图标
                    Text(String(idx + 1))
                      .fontSize(13).fontColor($r('app.color.text_tertiary')).width(28)
                    Text(r.isCorrect === AnswerStatus.CORRECT ? '✓' : '✗')
                      .fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor(r.isCorrect === AnswerStatus.CORRECT ? '#34C759' : '#FF3B30')
                      .margin({ right: 8 })

                    Text(r.question?.question ?? '')
                      .fontSize(14).fontColor($r('app.color.text_primary'))
                      .layoutWeight(1).maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(DateUtils.formatMs(r.timeSpentMs))
                      .fontSize(11).fontColor($r('app.color.text_tertiary')).margin({ left: 6 })
                  }

                  // 展开：显示我的答案 + 正确答案 + 解析
                  if (this.expandedId === r.id) {
                    Column() {
                      if (r.isCorrect !== AnswerStatus.CORRECT) {
                        Row() {
                          Text('我的答案：').fontSize(13).fontColor($r('app.color.text_secondary'))
                          Text(r.userAnswer || '（未作答）')
                            .fontSize(13).fontColor('#FF3B30').fontWeight(FontWeight.Medium)
                        }
                        .margin({ top: 8 })
                      }
                      Row() {
                        Text('正确答案：').fontSize(13).fontColor($r('app.color.text_secondary'))
                        Text(r.question?.answer ?? '').fontSize(13).fontColor('#34C759').fontWeight(FontWeight.Medium)
                      }
                      .margin({ top: 4 })

                      if (r.question?.explanation) {
                        Text('解析：' + r.question.explanation)
                          .fontSize(13).fontColor($r('app.color.text_secondary'))
                          .margin({ top: 6 }).lineHeight(18)
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .padding({ top: 8, left: 36 })
                  }
                }
                .padding(14)
                .backgroundColor(r.isCorrect === AnswerStatus.CORRECT
                  ? '#F0FDF4' : '#FFF5F5')
                .borderRadius(10)
                .border({
                  width: 1,
                  color: r.isCorrect === AnswerStatus.CORRECT ? '#BBF7D0' : '#FED7D7',
                })
                .onClick(() => {
                  this.expandedId = this.expandedId === r.id ? -1 : r.id;
                })
              }
            })
          }
          .layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: '加载中…' })
    }
  }

  @Builder SummaryItem(label: string, value: string, color: string = '') {
    Column() {
      Text(value)
        .fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor(color || $r('app.color.text_primary'))
      Text(label)
        .fontSize(12).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Center)
    .padding(12)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
    .layoutWeight(1)
    .margin({ right: 8 })
  }

  private rateStr(s: PracticeSession): string {
    if (!s.totalCount) return '--';
    return Math.round(s.correctCount / s.totalCount * 100) + '%';
  }

  private rateColor(s: PracticeSession): string {
    if (!s.totalCount) return '';
    const r = s.correctCount / s.totalCount;
    if (r >= 0.8) return '#34C759';
    if (r >= 0.6) return '#FF9500';
    return '#FF3B30';
  }
}
