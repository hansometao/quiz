import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { QuestionBank } from '../model/Models';
import { BankCard } from '../components/BankCard';
import { EmptyState, LoadingOverlay } from '../components/CommonComponents';

@Component
export struct BankListPage {
  @State banks: QuestionBank[] = [];
  @State loading: boolean = false;

  aboutToAppear() {
    this.loadBanks();
  }

  onPageShow() {
    this.loadBanks();
  }

  async loadBanks() {
    this.loading = true;
    try {
      this.banks = await DatabaseService.getInstance().banks.getAll();
    } catch (e) {
      console.error('加载题库失败', e);
    }
    this.loading = false;
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
            })
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
