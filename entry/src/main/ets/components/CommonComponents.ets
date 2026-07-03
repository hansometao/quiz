/** 空状态组件 */
@Component
export struct EmptyState {
  @Prop icon: string;
  @Prop title: string;
  @Prop subtitle: string;
  @Prop actionText: string;
  onAction: () => void = () => {};

  build() {
    Column() {
      Text(this.icon).fontSize(64).margin({ bottom: 16 })
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })
      if (this.subtitle) {
        Text(this.subtitle)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ bottom: 24 })
      }
      if (this.actionText) {
        Button(this.actionText)
          .height(42)
          .fontSize(15)
          .borderRadius(10)
          .backgroundColor($r('app.color.primary'))
          .fontColor(Color.White)
          .padding({ left: 24, right: 24 })
          .onClick(() => this.onAction())
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 80, bottom: 80 })
  }
}

// ─────────────────────────────────────────────────────────────

/** 全屏加载遮罩 */
@Component
export struct LoadingOverlay {
  @Prop visible: boolean;
  @Prop message: string;

  build() {
    if (this.visible) {
      Stack() {
        Column() {
          LoadingProgress()
            .width(48).height(48)
            .color($r('app.color.primary'))
          if (this.message) {
            Text(this.message)
              .fontSize(14)
              .fontColor(Color.White)
              .margin({ top: 12 })
          }
        }
        .padding(32)
        .backgroundColor('#CC000000')
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .hitTestBehavior(HitTestMode.Block)   // 拦截底层触摸，避免加载期间误触按钮
      .zIndex(999)
    }
  }
}

// ─────────────────────────────────────────────────────────────

/** 进度环组件（Canvas 自绘） */
@Component
export struct ProgressRing {
  @Prop @Watch('onPropChange') progress: number;   // 0~1
  @Prop @Watch('onPropChange') size: number;
  @Prop @Watch('onPropChange') strokeWidth: number;
  @Prop @Watch('onPropChange') color: string;
  @Prop @Watch('onPropChange') bgColor: string;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // 任一属性变化时触发重绘（@Prop 变化不会自动重绘 Canvas）
  private onPropChange(): void {
    this.draw();
  }

  build() {
    Canvas(this.ctx)
      .width(this.size)
      .height(this.size)
      .onReady(() => this.draw())
  }

  private draw(): void {
    const c = this.ctx;
    const s = this.size;
    const r = (s - this.strokeWidth) / 2;
    const cx = s / 2, cy = s / 2;

    c.clearRect(0, 0, s, s);

    // 背景圆
    c.beginPath();
    c.arc(cx, cy, r, 0, Math.PI * 2);
    c.strokeStyle = this.bgColor;
    c.lineWidth = this.strokeWidth;
    c.stroke();

    // 进度弧
    const angle = -Math.PI / 2 + (this.progress * Math.PI * 2);
    c.beginPath();
    c.arc(cx, cy, r, -Math.PI / 2, angle);
    c.strokeStyle = this.color;
    c.lineWidth = this.strokeWidth;
    c.lineCap = 'round';
    c.stroke();

    // 进度文字
    const pct = Math.round(this.progress * 100) + '%';
    c.fillStyle = '#1C1C1E';
    c.font = `bold ${Math.round(s * 0.22)}px sans-serif`;
    c.textAlign = 'center';
    c.textBaseline = 'middle';
    c.fillText(pct, cx, cy);
  }
}
