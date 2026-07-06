import { DatabaseService } from '../service/DatabaseService';
import { DateUtils } from '../utils/DateUtils';
import { LoadingOverlay } from '../components/CommonComponents';
import { OverallStat, DailyStat, CategoryStat } from '../service/repository/StatsRepository';

@Component
export struct AnalysisPage {
  @State daily: DailyStat[] = [];
  @State categories: CategoryStat[] = [];
  @State overall: OverallStat = { totalSessions: 0, totalQuestions: 0, avgCorrectRate: 0, totalDurationSec: 0 };
  @State loading: boolean = false;
  @State selectedDays: number = 14;
  @State lineCanvasWidth: number = 320;   // 折线图实际宽度（响应式）
  @State barCanvasWidth: number = 320;    // 柱状图实际宽度（响应式）

  private lineCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private barCtx:  CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private isLineChartDrawn: boolean = false;
  private isBarChartDrawn: boolean = false;
  // 代际 token：避免快速切换 7/14/30 天时旧请求覆盖新数据
  private loadGen: number = 0;
  private isAlive: boolean = true;
  @StorageProp('tabTick') @Watch('onTabTick') private tabTick: number = 0;
  @StorageProp('activeTab') private activeTab: number = 0;

  aboutToAppear() { this.loadStats(); }

  aboutToDisappear() {
    this.isAlive = false;
  }

  // Index 切换/回显时通过 AppStorage 通知刷新（@Component 子组件不接收 onPageShow）
  private onTabTick(): void {
    if (this.activeTab === 3) {
      this.loadStats();
    }
  }

  async loadStats() {
    const gen = ++this.loadGen;
    this.loading = true;
    const db = DatabaseService.getInstance();
    try {
      // 三个查询互不依赖，并行化缩短加载时间
      const [overall, daily, categories] = await Promise.all([
        db.stats.getOverall(),
        db.stats.getDailyStats(this.selectedDays),
        db.stats.getCategoryStats(),
      ]);
      // 切走页面或发起新请求后，丢弃过期结果
      if (!this.isAlive || gen !== this.loadGen) return;
      this.overall    = overall;
      this.daily      = daily;
      this.categories = categories;
    } catch (e) {
      if (!this.isAlive || gen !== this.loadGen) return;
      console.error('AnalysisPage loadStats 失败', e);
    } finally {
      if (this.isAlive && gen === this.loadGen) {
        this.loading = false;
        this.isLineChartDrawn = false;
        this.isBarChartDrawn = false;
        this.drawLineChart();
        this.drawBarChart();
      }
    }
  }

  // ── 折线图（近 N 天正确率趋势） ──
  private drawLineChart(): void {
    if (this.isLineChartDrawn) return;
    this.isLineChartDrawn = true;
    const c = this.lineCtx;
    const W = Math.max(this.lineCanvasWidth, 100);  // 响应式宽度，最小 100px
    const H = 140;
    const PAD = { left: 36, right: 12, top: 12, bottom: 28 };
    c.clearRect(0, 0, W, H);

    if (this.daily.length === 0) {
      c.fillStyle = '#AEAEB2';
      c.font = '13px sans-serif';
      c.textAlign = 'center';
      c.fillText('暂无数据', W / 2, H / 2);
      return;
    }

    const gW = W - PAD.left - PAD.right;
    const gH = H - PAD.top - PAD.bottom;

    // 网格线
    c.strokeStyle = '#E5E5EA';
    c.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const y = PAD.top + gH - i * gH / 4;
      c.beginPath(); c.moveTo(PAD.left, y); c.lineTo(PAD.left + gW, y); c.stroke();
      c.fillStyle = '#AEAEB2'; c.font = '10px sans-serif'; c.textAlign = 'right';
      c.fillText((i * 25) + '%', PAD.left - 4, y + 4);
    }

    const n = this.daily.length;
    const xStep = gW / Math.max(n - 1, 1);

    // 折线（正确率）
    c.beginPath();
    c.strokeStyle = '#0A84FF';
    c.lineWidth = 2;
    this.daily.forEach((d, i) => {
      const x = PAD.left + i * xStep;
      const y = PAD.top + gH * (1 - (d.correctRate ?? 0));
      if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
    });
    c.stroke();

    // 数据点
    this.daily.forEach((d, i) => {
      const x = PAD.left + i * xStep;
      const y = PAD.top + gH * (1 - (d.correctRate ?? 0));
      c.beginPath(); c.arc(x, y, 3, 0, Math.PI * 2);
      c.fillStyle = '#0A84FF'; c.fill();
    });

    // X轴日期（首尾）
    c.fillStyle = '#AEAEB2'; c.font = '10px sans-serif'; c.textAlign = 'center';
    c.fillText(this.daily[0].date.slice(5), PAD.left, H - 8);
    if (n > 1) c.fillText(this.daily[n-1].date.slice(5), PAD.left + gW, H - 8);
  }

  // ── 柱状图（各分类正确率） ──
  private drawBarChart(): void {
    if (this.isBarChartDrawn) return;
    this.isBarChartDrawn = true;
    const c = this.barCtx;
    const W = Math.max(this.barCanvasWidth, 100);  // 响应式宽度，最小 100px
    const H = 160;
    const PAD = { left: 80, right: 16, top: 12, bottom: 12 };
    c.clearRect(0, 0, W, H);

    if (this.categories.length === 0) {
      c.fillStyle = '#AEAEB2'; c.font = '13px sans-serif'; c.textAlign = 'center';
      c.fillText('暂无数据', W / 2, H / 2);
      return;
    }

    const cats = this.categories.slice(0, 8);
    const barH = (H - PAD.top - PAD.bottom) / cats.length - 6;
    const maxW = W - PAD.left - PAD.right;

    cats.forEach((cat, i) => {
      const y = PAD.top + i * (barH + 6);

      // 标签
      c.fillStyle = '#1C1C1E'; c.font = '11px sans-serif'; c.textAlign = 'right';
      const label = cat.category.length > 6 ? cat.category.slice(0, 6) + '…' : cat.category;
      c.fillText(label, PAD.left - 6, y + barH / 2 + 4);

      // 背景条
      c.fillStyle = '#E5E5EA';
      c.fillRect(PAD.left, y, maxW, barH);

      // 进度条
      const rate = cat.correctRate ?? 0;
      c.fillStyle = rate >= 0.8 ? '#34C759' : rate >= 0.6 ? '#FF9500' : '#FF3B30';
      c.fillRect(PAD.left, y, maxW * rate, barH);

      // 百分比
      c.fillStyle = '#6C6C70'; c.font = '10px sans-serif'; c.textAlign = 'left';
      c.fillText(Math.round(rate * 100) + '%', PAD.left + maxW * rate + 4, y + barH / 2 + 4);
    });
  }

  build() {
    Stack() {
      Column() {
        Text('数据分析').fontSize(22).fontWeight(FontWeight.Bold)
          .padding({ left: 16, top: 16, bottom: 12 }).alignSelf(ItemAlign.Start)

        Scroll() {
          Column() {
            // 综合统计卡片
            Grid() {
              GridItem() { this.StatCard('练习次数', String(this.overall.totalSessions), '次', '#0A84FF') }
              GridItem() { this.StatCard('作答题目', String(this.overall.totalQuestions), '题', '#34C759') }
              GridItem() { this.StatCard('平均正确率', (isNaN(this.overall.avgCorrectRate) ? 0 : Math.round(this.overall.avgCorrectRate * 100)) + '', '%', '#FF9500') }
              GridItem() { this.StatCard('总用时', DateUtils.formatDurationLabel(this.overall.totalDurationSec), '', '#AF52DE') }
            }
            .columnsTemplate('1fr 1fr')
            .rowsGap(10).columnsGap(10)
            .height(140)
            .margin({ bottom: 16 })

            // 折线图卡片
            Column() {
              Row() {
                Text('正确率趋势').fontSize(15).fontWeight(FontWeight.Bold).layoutWeight(1)
                // 切换天数
                ForEach([7, 14, 30], (d: number) => {
                  Text(d + '天')
                    .fontSize(12).padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(8)
                    .fontColor(this.selectedDays === d ? Color.White : $r('app.color.text_secondary'))
                    .backgroundColor(this.selectedDays === d ? $r('app.color.primary') : $r('app.color.bg_primary'))
                    .margin({ left: 6 })
                    .onClick(() => { this.selectedDays = d; this.loadStats(); })
                })
              }
              .margin({ bottom: 12 })

              Canvas(this.lineCtx)
                .width('100%').height(140)
                .onReady(() => this.drawLineChart())
                .onAreaChange((_, newArea) => {
                  if (newArea.width > 0 && newArea.width !== this.lineCanvasWidth) {
                    this.lineCanvasWidth = newArea.width as number;
                    this.isLineChartDrawn = false;   // 重置标志以触发响应式重绘
                    this.drawLineChart();
                  }
                })
            }
            .padding(16).backgroundColor($r('app.color.bg_card')).borderRadius(12)
            .margin({ bottom: 16 })

            // 分类掌握度柱状图
            Column() {
              Text('各分类掌握度').fontSize(15).fontWeight(FontWeight.Bold).margin({ bottom: 12 })
                .alignSelf(ItemAlign.Start)
              Canvas(this.barCtx)
                .width('100%').height(160)
                .onReady(() => this.drawBarChart())
                .onAreaChange((_, newArea) => {
                  if (newArea.width > 0 && newArea.width !== this.barCanvasWidth) {
                    this.barCanvasWidth = newArea.width as number;
                    this.isBarChartDrawn = false;   // 重置标志以触发响应式重绘
                    this.drawBarChart();
                  }
                })
            }
            .padding(16).backgroundColor($r('app.color.bg_card')).borderRadius(12)
            .margin({ bottom: 16 })

            Blank().height(20)
          }
          .padding(16)
        }
        .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: '' })
    }
  }

  @Builder StatCard(label: string, value: string, unit: string, color: string) {
    Column() {
      Row() {
        Text(value).fontSize(24).fontWeight(FontWeight.Bold).fontColor(color)
        Text(unit).fontSize(13).fontColor($r('app.color.text_secondary')).margin({ left: 2, top: 6 })
      }
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 4 })
    }
    .width('100%').padding(16)
    .backgroundColor($r('app.color.bg_card')).borderRadius(12)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}
