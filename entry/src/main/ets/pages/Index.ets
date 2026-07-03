import { BankListPage } from './BankListPage';
import { MistakePage } from './MistakePage';
import { HistoryPage } from './HistoryPage';
import { AnalysisPage } from './AnalysisPage';
import { SettingsPage } from './SettingsPage';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;

  // 通知当前激活的 Tab 子组件刷新数据（子组件通过 @Watch 监听 tabTick）
  private notifyTab(index: number): void {
    AppStorage.setOrCreate<number>('activeTab', index);
    AppStorage.setOrCreate<number>('tabTick', Date.now());
  }

  onPageShow() {
    // 从子页面返回时刷新当前 Tab（子组件自身不接收页面级生命周期）
    this.notifyTab(this.currentTab);
  }

  aboutToAppear() {
    this.notifyTab(this.currentTab);
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() { BankListPage() }
        .tabBar(this.TabBar('题库', '📚', 0))

      TabContent() { MistakePage() }
        .tabBar(this.TabBar('错题本', '✗', 1))

      TabContent() { HistoryPage() }
        .tabBar(this.TabBar('历史', '📋', 2))

      TabContent() { AnalysisPage() }
        .tabBar(this.TabBar('分析', '📊', 3))

      TabContent() { SettingsPage() }
        .tabBar(this.TabBar('设置', '⚙️', 4))
    }
    .onChange((index) => {
      this.currentTab = index;
      this.notifyTab(index);
    })
    .barHeight(56)
    .animationDuration(200)
    .backgroundColor($r('app.color.bg_primary'))
  }

  @Builder TabBar(label: string, icon: string, index: number) {
    Column() {
      Text(icon).fontSize(22)
      Text(label)
        .fontSize(11)
        .fontColor(this.currentTab === index ? $r('app.color.primary') : $r('app.color.text_secondary'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
