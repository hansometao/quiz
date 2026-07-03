import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { PracticeSession, AnswerRecord, AnswerStatus, PracticeMode, SessionStatus } from '../model/Models';
import { DateUtils } from '../utils/DateUtils';
import { ProgressRing, LoadingOverlay } from '../components/CommonComponents';

@Entry
@Component
struct ResultPage {
  private sessionId: number = (router.getParams() as Record<string, number>)['sessionId'];

  @State session: PracticeSession | null = null;
  @State records: AnswerRecord[] = [];
  @State loading: boolean = true;

  get correctCount():  number { return this.records.filter(r => r.isCorrect === AnswerStatus.CORRECT).length; }
  get wrongCount():    number { return this.records.filter(r => r.isCorrect === AnswerStatus.WRONG).length; }
  get skippedCount():  number { return this.records.filter(r => r.isCorrect === AnswerStatus.SKIPPED).length; }
  get totalCount():    number { return this.session?.totalCount ?? this.records.length; }
  get correctRate():   number { return this.totalCount > 0 ? this.correctCount / this.totalCount : 0; }
  get wrongRecords():  AnswerRecord[] { return this.records.filter(r => r.isCorrect === AnswerStatus.WRONG); }

  aboutToAppear() {
    this.loadData();
  }

  async loadData() {
    const db = DatabaseService.getInstance();
    // 先并发请求，避免串行等待
    const [sessions, records] = await Promise.all([
      db.getSessions(200),
      db.getAnswersBySession(this.sessionId),
    ]);
    this.records = records;
    // 从列表中查找对应 session
    const found = sessions.find(s => s.id === this.sessionId);
    if (found) {
      this.session = found;
    } else if (records.length > 0) {
      // 兜底：session 刚完成还未持久化，用记录推算
      const correct = records.filter(r => r.isCorrect === AnswerStatus.CORRECT).length;
      const score = records.reduce((sum, r) => sum + (r.isCorrect === AnswerStatus.CORRECT ? (r.question?.score ?? 1) : 0), 0);
      const times = records.map(r => r.answeredAt);
      const first = Math.min(...times);
      const last  = Math.max(...times);
      this.session = {
        id: this.sessionId,
        bankId: 0,
        mode: 'random' as PracticeMode,
        configJson: '{}',
        totalCount: records.length,
        correctCount: correct,
        durationSec: last - first,
        totalScore: score,
        status: 'completed' as SessionStatus,
        startedAt: first,
        finishedAt: last,
      } as PracticeSession;
    }
    this.loading = false;
  }

  build() {
    Stack() {
      Column() {
        // 顶部成绩卡
        Column() {
          Text('练习完成 🎉')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White).margin({ bottom: 16 })

          Row() {
            ProgressRing({
              progress:    this.correctRate,
              size:        100,
              strokeWidth: 10,
              color:       '#FFFFFF',
              bgColor:     '#FFFFFF40',
            })

            Column() {
              Row() {
                this.ScoreItem(String(this.correctCount),  '正确', '#4ADE80')
                this.ScoreItem(String(this.wrongCount),    '错误', '#FCA5A5')
                this.ScoreItem(String(this.skippedCount),  '跳过', '#FCD34D')
              }
              .margin({ bottom: 8 })

              Text('用时 ' + DateUtils.formatDuration(this.records.length > 0 ? this.calcDuration() : 0))
                .fontSize(13).fontColor('#FFFFFFCC')
            }
            .margin({ left: 24 })
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%').padding(24)
        .backgroundColor($r('app.color.primary'))
        .borderRadius({ bottomLeft: 20, bottomRight: 20 })

        // 操作按钮
        Row() {
          Button('再做一次')
            .layoutWeight(1).height(44).fontSize(15).borderRadius(12)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
            .border({ width: 1, color: $r('app.color.primary') })
            .onClick(() => router.back())
          Blank().width(12)
          Button('返回首页')
            .layoutWeight(1).height(44).fontSize(15).borderRadius(12)
            .backgroundColor($r('app.color.primary')).fontColor(Color.White)
            .onClick(() => router.pushUrl({ url: 'pages/Index' }))
        }
        .padding(16)

        // 错题列表
        if (this.wrongRecords.length > 0) {
          Text('本次错题（' + this.wrongRecords.length + '题）')
            .fontSize(15).fontWeight(FontWeight.Bold)
            .padding({ left: 16, bottom: 10 })
            .alignSelf(ItemAlign.Start)

          List({ space: 10 }) {
            ForEach(this.wrongRecords, (record: AnswerRecord) => {
              ListItem() {
                Column() {
                  Row() {
                    Text('✗').fontSize(16).fontColor($r('app.color.danger')).margin({ right: 8 })
                    Text(record.question?.question ?? '')
                      .fontSize(14).fontColor($r('app.color.text_primary'))
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  Row() {
                    Text('你的答案：' + (record.userAnswer || '未作答'))
                      .fontSize(12).fontColor($r('app.color.danger'))
                    Text('  正确答案：' + (record.question?.answer ?? ''))
                      .fontSize(12).fontColor($r('app.color.success'))
                  }
                  .margin({ top: 6 })
                }
                .padding(12)
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(10)
                .border({ width: 1, color: '#FFE0E0' })
              }
            })
          }
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: '' })
    }
  }

  @Builder ScoreItem(value: string, label: string, color: string) {
    Column() {
      Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor(color)
      Text(label).fontSize(11).fontColor('#FFFFFFCC').margin({ top: 2 })
    }
    .margin({ right: 16 })
  }

  private calcDuration(): number {
    if (!this.records || this.records.length === 0) return 0;
    const times = this.records.map(r => r.answeredAt);
    const first = Math.min(...times);
    const last  = Math.max(...times);
    return last - first;
  }
}
