import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { QuestionBank } from '../model/Models';
import { BankCard } from '../components/BankCard';
import { EmptyState, LoadingOverlay } from '../components/CommonComponents';

@Component
export struct BankListPage {
  @State banks: QuestionBank[] = [];
  @State loading: boolean = false;
  @StorageProp('tabTick') @Watch('onTabTick') private tabTick: number = 0;
  @StorageProp('activeTab') private activeTab: number = 0;
  private isAlive: boolean = true;

  aboutToAppear() {
    this.loadBanks();
  }

  aboutToDisappear() {
    this.isAlive = false;
  }

  // Index 切换/回显时通过 AppStorage 通知刷新（@Component 子组件不接收 onPageShow）
  private onTabTick(): void {
    if (this.activeTab === 0) {
      this.loadBanks();
    }
  }

  async loadBanks() {
    this.loading = true;
    try {
      // 确保数据库初始化完成后再查询，解决冷启动时子组件 aboutToAppear 先于
      // Index 的 async aboutToAppear 完成导致的竞态
      await DatabaseService.getInstance().ready();
      const banks = await DatabaseService.getInstance().banks.getAll();
      if (!this.isAlive) return;
      this.banks = banks;
    } catch (e) {
      if (!this.isAlive) return;
      console.error('加载题库失败', e);
    } finally {
      if (this.isAlive) this.loading = false;
    }
  }

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Text('题库').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Blank()
          Button({ type: ButtonType.Circle }) {
            Text('+').fontSize(24).fontColor(Color.White)
          }
          .width(40).height(40)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => router.pushUrl({ url: 'pages/ImportPage' }))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        // 题库列表
        if (this.banks.length === 0 && !this.loading) {
          EmptyState({
            icon: '📚',
            title: '还没有题库',
            subtitle: '点击右上角 + 导入 Excel 题库',
            actionText: '导入题库',
            onAction: () => router.pushUrl({ url: 'pages/ImportPage' }),
          })
        } else {
          List({ space: 12 }) {
            ForEach(this.banks, (bank: QuestionBank) => {
              ListItem() {
                BankCard({
                  bank,
                  onPractice: () => router.pushUrl({
                    url: 'pages/PracticeConfigPage',
                    params: { bankId: bank.id, bankName: bank.name }
                  }),
                  onDetail: () => router.pushUrl({
                    url: 'pages/BankDetailPage',
                    params: { bankId: bank.id }
                  }),
                })
              }
            }, (bank: QuestionBank) => bank.id.toString())
          }
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: '加载中...' })
    }
  }
}
