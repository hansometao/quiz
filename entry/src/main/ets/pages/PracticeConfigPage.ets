import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { PracticeMode, PracticeConfig, QuestionType, Difficulty } from '../model/Models';
import { QuizEngine } from '../service/QuizEngine';

@Entry
@Component
struct PracticeConfigPage {
  private bankId: number = (router.getParams() as Record<string, number>)['bankId'] ?? 0;
  private bankName: string = (router.getParams() as Record<string, string>)['bankName'] ?? '练习';

  @State selectedMode: PracticeMode = PracticeMode.RANDOM;
  @State totalCount: number = 20;
  @State timeLimitMin: number = 0;  // 0=不限时
  @State showExplanation: boolean = true;
  @State allowSkip: boolean = true;
  @State categories: string[] = [];
  @State selectedCategories: string[] = [];
  @State maxCount: number = 0;

  private modes: PracticeMode[] = [
    PracticeMode.SEQUENTIAL, PracticeMode.RANDOM, PracticeMode.EXAM,
    PracticeMode.MISTAKE, PracticeMode.CATEGORY, PracticeMode.DIFFICULTY,
  ];

  aboutToAppear() {
    this.loadMeta();
  }

  async loadMeta() {
    const db = DatabaseService.getInstance();
    const bank = await db.getBankById(this.bankId);
    this.maxCount = bank?.totalCount ?? 0;
    this.totalCount = Math.min(20, this.maxCount);
    this.categories = await db.getCategories(this.bankId);
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button({ type: ButtonType.Circle }) {
          Text('←').fontSize(18).fontColor($r('app.color.text_primary'))
        }
        .width(36).height(36).backgroundColor(Color.Transparent)
        .onClick(() => router.back())

        Text(this.bankName).fontSize(18).fontWeight(FontWeight.Bold).margin({ left: 8 })
      }
      .width('100%').padding(16)

      Scroll() {
        Column() {
          // 练习模式
          this.SectionTitle('练习模式')
          Grid() {
            ForEach(this.modes, (mode: PracticeMode) => {
              GridItem() {
                Text(QuizEngine.modeLabel(mode))
                  .fontSize(14).textAlign(TextAlign.Center)
                  .width('100%').height(44)
                  .borderRadius(10)
                  .fontColor(this.selectedMode === mode ? Color.White : $r('app.color.text_primary'))
                  .backgroundColor(this.selectedMode === mode ? $r('app.color.primary') : $r('app.color.bg_card'))
                  .border({ width: 1, color: this.selectedMode === mode ? $r('app.color.primary') : $r('app.color.border') })
                  .onClick(() => this.selectedMode = mode)
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr')
          .rowsGap(10).columnsGap(10)
          .height(100)
          .margin({ bottom: 20 })

          // 题目数量
          this.SectionTitle('题目数量（共 ' + this.maxCount + ' 题）')
          Row() {
            Slider({
              value: this.totalCount,
              min: 5,
              max: this.maxCount || 100,
              step: 5,
            })
            .layoutWeight(1)
            .onChange((v) => { this.totalCount = Math.round(v); })

            Text(String(this.totalCount))
              .fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary')).width(40).textAlign(TextAlign.End)
          }
          .margin({ bottom: 20 })

          // 分类选择（仅分类模式）
          if (this.selectedMode === PracticeMode.CATEGORY && this.categories.length > 0) {
            this.SectionTitle('选择分类')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.categories, (cat: string) => {
                Text(cat)
                  .fontSize(13)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .fontColor(this.selectedCategories.includes(cat) ? Color.White : $r('app.color.text_primary'))
                  .backgroundColor(this.selectedCategories.includes(cat) ? $r('app.color.primary') : $r('app.color.bg_card'))
                  .border({ width: 1, color: this.selectedCategories.includes(cat) ? $r('app.color.primary') : $r('app.color.border') })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => this.toggleCategory(cat))
              })
            }
            .margin({ bottom: 20 })
          }

          // 时间限制（模拟考试模式）
          if (this.selectedMode === PracticeMode.EXAM) {
            this.SectionTitle('时间限制（分钟，0=不限时）')
            Row() {
              Slider({ value: this.timeLimitMin, min: 0, max: 180, step: 5 })
                .layoutWeight(1)
                .onChange((v) => { this.timeLimitMin = Math.round(v); })
              Text(this.timeLimitMin === 0 ? '不限' : this.timeLimitMin + '分')
                .fontSize(14).fontColor($r('app.color.primary')).width(50).textAlign(TextAlign.End)
            }
            .margin({ bottom: 20 })
          }

          // 其他选项
          this.SectionTitle('其他选项')
          this.SwitchRow('答题后显示解析', this.showExplanation, (v: boolean) => this.showExplanation = v)
          this.SwitchRow('允许跳过题目',   this.allowSkip,       (v: boolean) => this.allowSkip = v)

          Blank().height(100)
        }
        .padding(16)
      }
      .layoutWeight(1)

      // 底部开始按钮
      Button('开始练习')
        .width('90%').height(52).fontSize(17).borderRadius(14)
        .backgroundColor($r('app.color.primary')).fontColor(Color.White)
        .margin({ bottom: 20 })
        .onClick(() => this.startPractice())
    }
    .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))
  }

  @Builder SectionTitle(title: string) {
    Text(title)
      .fontSize(14).fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_secondary'))
      .margin({ bottom: 10 })
      .alignSelf(ItemAlign.Start)
  }

  @Builder SwitchRow(label: string, value: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(label).fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange(onChange)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.bg_card')).borderRadius(10)
    .margin({ bottom: 8 })
  }

  private toggleCategory(cat: string): void {
    const idx = this.selectedCategories.indexOf(cat);
    if (idx >= 0) {
      this.selectedCategories = this.selectedCategories.filter(c => c !== cat);
    } else {
      this.selectedCategories = [...this.selectedCategories, cat];
    }
  }

  private startPractice(): void {
    // TODO: 题型/难度筛选 UI 待补充（当前只有分类选择有 UI，题型和难度选择器尚未实现）
    const config: PracticeConfig = {
      mode:            this.selectedMode,
      totalCount:      this.totalCount,
      types:           [],
      categories:      this.selectedCategories,
      difficulties:    [],
      timeLimitSec:    this.timeLimitMin * 60,
      showExplanation: this.showExplanation,
      allowSkip:       this.allowSkip,
    };
    router.pushUrl({
      url: 'pages/QuizPage',
      params: { bankId: this.bankId, config: JSON.stringify(config) }
    });
  }
}
