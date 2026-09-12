import { QuestionBank } from '../model/Models';
import { DateUtils } from '../utils/DateUtils';

/** 题库卡片组件 */
@Component
export struct BankCard {
  @Prop bank: QuestionBank;
  onPractice: () => void = () => {};
  onDetail: () => void = () => {};

  build() {
    Column() {
      // 标题行
      Row() {
        Text('📚')
          .fontSize(22)
          .margin({ right: 10 })
        Column() {
          Text(this.bank.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.bank.description) {
            Text(this.bank.description)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().margin({ top: 10, bottom: 10 }).color($r('app.color.border'))

      // 统计信息
      Row() {
        this.StatItem('共 ' + this.bank.totalCount + ' 题')
        this.StatItem('练习 ' + (this.bank.practiceCount ?? 0) + ' 次')
        this.StatItem('正确率 ' + this.formatRate(this.bank.avgCorrectRate))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 上次练习时间
      if (this.bank.lastPracticeAt) {
        Text('上次：' + DateUtils.formatDate(this.bank.lastPracticeAt))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 6 })
          .alignSelf(ItemAlign.Start)
      }

      Divider().margin({ top: 10, bottom: 10 }).color($r('app.color.border'))

      // 操作按钮
      Row() {
        Button('查看详情')
          .layoutWeight(1)
          .height(36)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.primary'))
          .border({ width: 1, color: $r('app.color.primary') })
          .borderRadius(8)
          .onClick(() => this.onDetail())
        Blank().width(12)
        Button('开始练习')
          .layoutWeight(1)
          .height(36)
          .fontSize(14)
          .backgroundColor($r('app.color.primary'))
          .fontColor(Color.White)
          .borderRadius(8)
          .onClick(() => this.onPractice())
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(12)
    .shadow({ radius: 4, color: $r('app.color.shadow'), offsetX: 0, offsetY: 2 })
  }

  @Builder StatItem(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
  }

  private formatRate(rate: number | undefined): string {
    // 0 是合法的正确率，不能用 !rate 误判；只有 undefined/NaN 才显示 '--%'
    if (rate === undefined || rate === null || isNaN(rate)) return '--%';
    return Math.round(rate * 100) + '%';
  }
}
