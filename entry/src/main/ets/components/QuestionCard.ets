import { Question, QuestionType, Difficulty } from '../model/Models';
import { QuizEngine } from '../service/QuizEngine';

interface OptionInfo {
  key: string;
  text: string;
}

/** 答题选项组件 */
@Component
export struct OptionItem {
  @Prop optionKey: string;
  @Prop text: string;
  @Prop selected: boolean;
  @Prop submitted: boolean;
  @Prop isCorrect: boolean;  // 该选项是否在正确答案中
  onSelect: () => void = () => {};

  build() {
    Row() {
      // 选项字母圆圈
      Text(this.optionKey)
        .width(28).height(28)
        .textAlign(TextAlign.Center)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .borderRadius(14)
        .fontColor(this.getLetterColor())
        .backgroundColor(this.getLetterBg())
        .border({ width: 1.5, color: this.getLetterBorderColor() })
        .margin({ right: 12 })

      Text(this.text)
        .layoutWeight(1)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(22)

      // 提交后显示图标
      if (this.submitted && this.isCorrect) {
        Text('✓').fontSize(18).fontColor($r('app.color.success'))
      } else if (this.submitted && this.selected && !this.isCorrect) {
        Text('✗').fontSize(18).fontColor($r('app.color.danger'))
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(10)
    .border({ width: 1.5, color: this.getBorderColor() })
    .backgroundColor(this.getBgColor())
    .onClick(() => {
      if (!this.submitted) this.onSelect();
    })
    .animation({ duration: 150 })
    .margin({ bottom: 10 })
  }

  private getBgColor(): ResourceColor {
    if (!this.submitted) {
      return this.selected ? $r('app.color.primary_light') : $r('app.color.bg_card');
    }
    if (this.isCorrect) return $r('app.color.success_light');
    if (this.selected && !this.isCorrect) return $r('app.color.danger_light');
    return $r('app.color.bg_card');
  }

  private getBorderColor(): ResourceColor {
    if (!this.submitted) {
      return this.selected ? $r('app.color.primary') : $r('app.color.border');
    }
    if (this.isCorrect) return $r('app.color.success');
    if (this.selected && !this.isCorrect) return $r('app.color.danger');
    return $r('app.color.border');
  }

  private getLetterBg(): ResourceColor {
    if (!this.submitted) {
      return this.selected ? $r('app.color.primary') : Color.Transparent;
    }
    if (this.isCorrect) return $r('app.color.success');
    if (this.selected && !this.isCorrect) return $r('app.color.danger');
    return Color.Transparent;
  }

  private getLetterColor(): ResourceColor {
    if (!this.submitted && !this.selected) return $r('app.color.text_secondary');
    return Color.White;
  }

  private getLetterBorderColor(): ResourceColor {
    if (!this.submitted) {
      return this.selected ? $r('app.color.primary') : $r('app.color.border');
    }
    if (this.isCorrect) return $r('app.color.success');
    if (this.selected && !this.isCorrect) return $r('app.color.danger');
    return $r('app.color.border');
  }
}

// ─────────────────────────────────────────────────────────────

/** 题目卡片组件（包含题干 + 选项/判断/填空） */
@Component
export struct QuestionCard {
  @Prop @Watch('onQuestionChange') question: Question;
  @Prop selectedAnswer: string;     // 当前已选答案
  @Prop submitted: boolean;         // 是否已提交
  onAnswerChange: (answer: string) => void = () => {};

  @State fillInput: string = '';

  // 切题时同步已存的填空答案，避免残留上一题输入且不回显已答内容
  private onQuestionChange(): void {
    this.fillInput = this.question.type === QuestionType.FILL ? (this.selectedAnswer ?? '') : '';
  }

  build() {
    Column() {
      // 题型标签 + 难度
      Row() {
        Text(QuizEngine.typeLabel(this.question.type))
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .backgroundColor($r('app.color.primary_light'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(4)

        Text(QuizEngine.difficultyLabel(this.question.difficulty))
          .fontSize(12)
          .fontColor(this.getDifficultyColor())
          .backgroundColor(this.getDifficultyBg())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(4)
          .margin({ left: 8 })

        if (this.question.category) {
          Text(this.question.category)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.bg_primary'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(4)
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 题干
      Text(this.question.question)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(24)
        .width('100%')
        .margin({ bottom: 18 })

      // 选项区域（根据题型不同）
      if (this.question.type === QuestionType.SINGLE || this.question.type === QuestionType.MULTI) {
        this.ChoiceOptions()
      } else if (this.question.type === QuestionType.JUDGE) {
        this.JudgeOptions()
      } else if (this.question.type === QuestionType.FILL) {
        this.FillInput()
      } else {
        this.EssayView()
      }

      // 提交后显示解析
      if (this.submitted && this.question.explanation) {
        Divider().margin({ top: 14, bottom: 14 }).color($r('app.color.border'))
        Column() {
          Text('解析').fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.primary')).margin({ bottom: 6 })
          Text(this.question.explanation)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(22)
            .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.info_light'))
        .borderRadius(8)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(12)
  }

  @Builder ChoiceOptions() {
    Column() {
      ForEach(this.getOptions(), (opt: OptionInfo) => {
        OptionItem({
          optionKey:  opt.key,
          text:       opt.text,
          selected:   this.isSelected(opt.key),
          submitted:  this.submitted,
          isCorrect:  this.question.answer.includes(opt.key),
          onSelect:   () => this.handleOptionSelect(opt.key),
        })
      }, (opt: OptionInfo) => opt.key)
    }
  }

  @Builder JudgeOptions() {
    Row() {
      Button('✓ 正确')
        .layoutWeight(1)
        .height(44)
        .fontSize(15)
        .borderRadius(10)
        .backgroundColor(this.judgeButtonBg('正确'))
        .fontColor(this.judgeButtonTextColor('正确'))
        .border({ width: 1.5, color: this.judgeButtonBorder('正确') })
        .onClick(() => { if (!this.submitted) this.onAnswerChange('正确'); })
      Blank().width(12)
      Button('✗ 错误')
        .layoutWeight(1)
        .height(44)
        .fontSize(15)
        .borderRadius(10)
        .backgroundColor(this.judgeButtonBg('错误'))
        .fontColor(this.judgeButtonTextColor('错误'))
        .border({ width: 1.5, color: this.judgeButtonBorder('错误') })
        .onClick(() => { if (!this.submitted) this.onAnswerChange('错误'); })
    }
  }

  @Builder FillInput() {
    Column() {
      TextInput({ placeholder: '请输入答案...', text: this.fillInput })
        .onChange((v) => {
          this.fillInput = v;
          this.onAnswerChange(v);
        })
        .enabled(!this.submitted)
        .fontSize(15)
        .height(48)
        .borderRadius(8)
      if (this.submitted) {
        Text('参考答案：' + this.question.answer)
          .fontSize(14)
          .fontColor($r('app.color.success'))
          .margin({ top: 8 })
      }
    }
  }

  @Builder EssayView() {
    Column() {
      if (!this.submitted) {
        Text('简答题：请思考后查看参考答案')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      } else {
        Text('参考答案：')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 6 })
        Text(this.question.answer)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
          .width('100%')
      }
    }
    .width('100%')
  }

  private getOptions(): OptionInfo[] {
    const opts: OptionInfo[] = [];
    if (this.question.optionA) opts.push({ key: 'A', text: this.question.optionA });
    if (this.question.optionB) opts.push({ key: 'B', text: this.question.optionB });
    if (this.question.optionC) opts.push({ key: 'C', text: this.question.optionC });
    if (this.question.optionD) opts.push({ key: 'D', text: this.question.optionD });
    if (this.question.optionE) opts.push({ key: 'E', text: this.question.optionE });
    return opts;
  }

  private isSelected(key: string): boolean {
    return this.selectedAnswer.includes(key);
  }

  private handleOptionSelect(key: string): void {
    if (this.question.type === QuestionType.SINGLE) {
      this.onAnswerChange(key);
    } else {
      // 多选：切换选中
      let current = this.selectedAnswer;
      if (current.includes(key)) {
        // 用 split+join 而非 replace，确保所有匹配的字母都被移除（如 ABCA 取消 A → BC）
        current = current.split(key).join('');
      } else {
        const letters = (current + key).split('').sort().join('');
        current = letters;
      }
      this.onAnswerChange(current);
    }
  }

  private judgeButtonBg(val: string): ResourceColor {
    if (!this.submitted) {
      return this.selectedAnswer === val ? $r('app.color.primary') : Color.Transparent;
    }
    if (val === this.question.answer) return $r('app.color.success');
    if (this.selectedAnswer === val && val !== this.question.answer) return $r('app.color.danger');
    return Color.Transparent;
  }

  private judgeButtonTextColor(val: string): ResourceColor {
    if (this.selectedAnswer === val || (this.submitted && val === this.question.answer)) return Color.White;
    return $r('app.color.text_primary');
  }

  private judgeButtonBorder(val: string): ResourceColor {
    if (!this.submitted) return this.selectedAnswer === val ? $r('app.color.primary') : $r('app.color.border');
    if (val === this.question.answer) return $r('app.color.success');
    if (this.selectedAnswer === val) return $r('app.color.danger');
    return $r('app.color.border');
  }

  private getDifficultyColor(): ResourceColor {
    switch (this.question.difficulty) {
      case 1: return $r('app.color.success');
      case 3: return $r('app.color.danger');
      default: return $r('app.color.warning');
    }
  }

  private getDifficultyBg(): ResourceColor {
    switch (this.question.difficulty) {
      case 1: return $r('app.color.success_light');
      case 3: return $r('app.color.danger_light');
      default: return $r('app.color.warning_light');
    }
  }
}
