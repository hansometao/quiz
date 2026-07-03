/**
 * BankDetailPage.ets
 * 题库详情页
 *   - 题目列表（LazyForEach 虚拟化）
 *   - 分类/难度/类型 筛选 Chip
 *   - 搜索框
 *   - 滚动到底自动加载下一页
 *   - 长按题目弹出上下文菜单（删除 / 收藏 / 添加笔记）
 */

import router from '@ohos.router';
import { DatabaseService } from '../service/DatabaseService';
import { QuestionBank, Question, QuestionType, Difficulty } from '../model/Models';
import { QuizEngine } from '../service/QuizEngine';
import { EmptyState, LoadingOverlay } from '../components/CommonComponents';
import { DateUtils } from '../utils/DateUtils';
import { ArrayDataSource } from '../utils/LazyDataSource';

@Entry
@Component
struct BankDetailPage {
  private bankId: number = (router.getParams() as Record<string, number> | null)?.['bankId'] ?? 0;

  @State bank: QuestionBank | null = null;
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State searchText: string = '';
  @State filterType: QuestionType | 'all' = 'all';
  @State filterDifficulty: Difficulty | 0 = 0;
  @State showDeleteConfirm: boolean = false;
  @State selectedQuestion: Question | null = null;
  @State noteText: string = '';
  @State showNoteDialog: boolean = false;
  @State toastMsg: string = '';
  @State showToast: boolean = false;

  private ds: ArrayDataSource<Question> = new ArrayDataSource<Question>();
  private page: number = 0;
  private hasMore: boolean = true;
  readonly PAGE_SIZE = 30;

  aboutToAppear() { this.loadData(true); }

  async loadData(reset: boolean = false) {
    if (reset) {
      this.page = 0;
      this.hasMore = true;
      this.loading = true;
      this.ds.clear();
    }
    if (!this.hasMore) {
      if (reset) this.loading = false;   // 避免重置时 loading 卡死
      return;
    }
    if (this.loadingMore) {
      if (reset) this.loading = false;   // 重置与进行中的加载冲突时释放遮罩
      return;
    }

    this.loadingMore = !reset;
    const db = DatabaseService.getInstance();

    if (reset) {
      this.bank = await db.banks.getById(this.bankId);
    }

    const questions = await db.questions.getByBank(this.bankId, {
      types: this.filterType !== 'all' ? [this.filterType as QuestionType] : undefined,
      difficulties: this.filterDifficulty !== 0 ? [this.filterDifficulty as Difficulty] : undefined,
      limit: this.PAGE_SIZE,
      offset: this.page * this.PAGE_SIZE,
    });

    if (questions.length < this.PAGE_SIZE) this.hasMore = false;
    questions.forEach(q => this.ds.push(q));
    this.page++;

    this.loading = false;
    this.loadingMore = false;
  }

  async deleteQuestion(q: Question) {
    const db = DatabaseService.getInstance();
    try {
      await db.questions.deleteById(q.id);
      await db.banks.refreshCount(this.bankId);
      this.bank = await db.banks.getById(this.bankId);
      this.showMsg('已删除题目');
      this.loadData(true);
    } catch {
      this.showMsg('删除失败');
    }
    this.showDeleteConfirm = false;
    this.selectedQuestion = null;
  }

  async toggleStar(q: Question) {
    const db = DatabaseService.getInstance();
    await db.questions.updateMeta(q.id, { isStarred: !q.isStarred });
    this.loadData(true);
  }

  async saveNote() {
    if (!this.selectedQuestion) return;
    const db = DatabaseService.getInstance();
    await db.questions.updateMeta(this.selectedQuestion.id, { userNote: this.noteText });
    this.showMsg('笔记已保存');
    this.showNoteDialog = false;
    this.selectedQuestion = null;
    this.loadData(true);
  }

  showMsg(msg: string) {
    this.toastMsg = msg;
    this.showToast = true;
    setTimeout(() => { this.showToast = false; }, 2000);
  }

  build() {
    Stack() {
      Column() {
        // ── 导航栏 ──
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('←').fontSize(18).fontColor($r('app.color.text_primary'))
          }
          .width(36).height(36).backgroundColor(Color.Transparent)
          .onClick(() => router.back())

          Text(this.bank?.name ?? '题库详情')
            .fontSize(18).fontWeight(FontWeight.Bold).margin({ left: 8 }).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

          Button('练习').height(34).fontSize(14).borderRadius(10)
            .backgroundColor($r('app.color.primary')).fontColor(Color.White)
            .onClick(() => router.pushUrl({
              url: 'pages/PracticeConfigPage',
              params: { bankId: this.bankId, bankName: this.bank?.name ?? '' }
            }))
        }
        .width('100%').padding(16)

        // ── 统计卡 ──
        if (this.bank) {
          Row() {
            this.StatChip('共 ' + this.bank.totalCount + ' 题',          '#0A84FF')
            this.StatChip('练习 ' + (this.bank.practiceCount ?? 0) + ' 次', '#34C759')
            this.StatChip('正确率 ' + this.formatRate(this.bank.avgCorrectRate), '#FF9500')
          }
          .padding({ left: 16, right: 16, bottom: 8 })
        }

        // ── 筛选 Chips ──
        Scroll() {
          Row() {
            this.FilterChip('全部',   this.filterType === 'all',
              () => { this.filterType = 'all'; this.loadData(true); })
            this.FilterChip('单选', this.filterType === QuestionType.SINGLE,
              () => { this.filterType = QuestionType.SINGLE; this.loadData(true); })
            this.FilterChip('多选', this.filterType === QuestionType.MULTI,
              () => { this.filterType = QuestionType.MULTI; this.loadData(true); })
            this.FilterChip('判断', this.filterType === QuestionType.JUDGE,
              () => { this.filterType = QuestionType.JUDGE; this.loadData(true); })
            this.FilterChip('填空', this.filterType === QuestionType.FILL,
              () => { this.filterType = QuestionType.FILL; this.loadData(true); })
            this.FilterChip('简答', this.filterType === QuestionType.ESSAY,
              () => { this.filterType = QuestionType.ESSAY; this.loadData(true); })
            Blank().width(8)
            this.FilterChip('易', this.filterDifficulty === Difficulty.EASY,
              () => { this.filterDifficulty = this.filterDifficulty === Difficulty.EASY ? 0 : Difficulty.EASY; this.loadData(true); })
            this.FilterChip('中', this.filterDifficulty === Difficulty.MEDIUM,
              () => { this.filterDifficulty = this.filterDifficulty === Difficulty.MEDIUM ? 0 : Difficulty.MEDIUM; this.loadData(true); })
            this.FilterChip('难', this.filterDifficulty === Difficulty.HARD,
              () => { this.filterDifficulty = this.filterDifficulty === Difficulty.HARD ? 0 : Difficulty.HARD; this.loadData(true); })
          }
          .padding({ left: 12, right: 12 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%').margin({ bottom: 8 })

        // ── 题目列表 ──
        if (this.loading) {
          Blank().layoutWeight(1)
        } else if (this.ds.totalCount() === 0) {
          EmptyState({
            icon: '📋',
            title: '暂无题目',
            subtitle: '当前筛选条件下没有题目',
            actionText: '',
          })
        } else {
          List({ space: 10 }) {
            LazyForEach(this.ds, (q: Question) => {
              ListItem() {
                Column() {
                  Row() {
                    Text(QuizEngine.typeLabel(q.type))
                      .fontSize(11).fontColor($r('app.color.primary'))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('#E8F2FF').borderRadius(4)
                    Text(' Q' + q.seqNo)
                      .fontSize(11).fontColor($r('app.color.text_tertiary')).margin({ left: 4 })
                    Blank()
                    if (q.isStarred) {
                      Text('⭐').fontSize(13).margin({ right: 4 })
                    }
                    Text(QuizEngine.difficultyLabel(q.difficulty))
                      .fontSize(11).fontColor($r('app.color.text_secondary'))
                  }
                  .margin({ bottom: 6 })

                  Text(q.question)
                    .fontSize(14).fontColor($r('app.color.text_primary'))
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(20)

                  Text('答案：' + q.answer)
                    .fontSize(12).fontColor($r('app.color.success')).margin({ top: 6 })

                  if (q.userNote) {
                    Text('📝 ' + q.userNote)
                      .fontSize(11).fontColor($r('app.color.text_secondary')).margin({ top: 4 })
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .padding(14).backgroundColor($r('app.color.bg_card')).borderRadius(10)
                .gesture(LongPressGesture().onAction(() => {
                  this.selectedQuestion = q;
                  this.noteText = q.userNote ?? '';
                }))
                .bindContextMenu(this.selectedQuestion !== null && this.selectedQuestion.id === q.id, this.ContextMenu(q),
                  { placement: Placement.Bottom })
              }
            }, (q: Question) => String(q.id))

            // 加载更多触发器
            if (this.hasMore) {
              ListItem() {
                Row() {
                  if (this.loadingMore) {
                    LoadingProgress().width(24).height(24).color($r('app.color.primary'))
                  } else {
                    Text('上拉加载更多…').fontSize(13).fontColor($r('app.color.text_tertiary'))
                  }
                }
                .justifyContent(FlexAlign.Center).width('100%').padding(16)
                .onClick(() => this.loadData())
              }
            }
          }
          .layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
          .onScrollEdge((side) => {
            if (side === Edge.Bottom) this.loadData();
          })
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: '加载中…' })

      // ── 删除确认弹窗 ──
      if (this.showDeleteConfirm && this.selectedQuestion) {
        Stack() {
          Column()
            .width('100%').height('100%').backgroundColor('#80000000')
            .onClick(() => { this.showDeleteConfirm = false; this.selectedQuestion = null; })
          Column() {
            Text('确认删除').fontSize(17).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
            Text('删除后不可恢复。确定要删除这道题吗？')
              .fontSize(14).fontColor($r('app.color.text_secondary')).margin({ bottom: 20 }).textAlign(TextAlign.Center)
            Row() {
              Button('取消').layoutWeight(1).height(44).borderRadius(10)
                .backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary'))
                .border({ width: 1, color: $r('app.color.border') })
                .onClick(() => { this.showDeleteConfirm = false; this.selectedQuestion = null; })
              Blank().width(12)
              Button('删除').layoutWeight(1).height(44).borderRadius(10)
                .backgroundColor($r('app.color.danger')).fontColor(Color.White)
                .onClick(() => this.deleteQuestion(this.selectedQuestion!))
            }
          }
          .padding(24).backgroundColor($r('app.color.bg_card')).borderRadius(16).width('85%')
          .position({ x: '7.5%', y: '35%' })
        }
        .width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(100)
      }

      // ── 笔记弹窗 ──
      if (this.showNoteDialog && this.selectedQuestion) {
        Stack() {
          Column()
            .width('100%').height('100%').backgroundColor('#80000000')
            .onClick(() => { this.showNoteDialog = false; this.selectedQuestion = null; })
          Column() {
            Text('添加笔记').fontSize(17).fontWeight(FontWeight.Bold).margin({ bottom: 12 })
            TextArea({ text: this.noteText, placeholder: '输入笔记内容…' })
              .height(100).width('100%').borderRadius(8).onChange((v) => { this.noteText = v; })
            Row() {
              Button('取消').layoutWeight(1).height(44).borderRadius(10)
                .backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary'))
                .border({ width: 1, color: $r('app.color.border') }).margin({ top: 16 })
                .onClick(() => { this.showNoteDialog = false; this.selectedQuestion = null; })
              Blank().width(12)
              Button('保存').layoutWeight(1).height(44).borderRadius(10)
                .backgroundColor($r('app.color.primary')).fontColor(Color.White).margin({ top: 16 })
                .onClick(() => this.saveNote())
            }
          }
          .padding(24).backgroundColor($r('app.color.bg_card')).borderRadius(16).width('90%')
          .position({ x: '5%', y: '25%' })
        }
        .width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(100)
      }

      // ── Toast ──
      if (this.showToast) {
        Text(this.toastMsg)
          .fontSize(14).fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          .backgroundColor('#CC333333').borderRadius(24)
          .position({ x: '10%', y: '82%' }).width('80%').textAlign(TextAlign.Center).zIndex(200)
      }
    }
    .width('100%').height('100%')
  }

  @Builder ContextMenu(q: Question) {
    Menu() {
      MenuItem({ startIcon: $r('sys.media.ohos_ic_public_favor'), content: q.isStarred ? '取消收藏' : '收藏题目' })
        .onClick(() => this.toggleStar(q))
      MenuItem({ startIcon: $r('sys.media.ohos_ic_public_edit'), content: '添加笔记' })
        .onClick(() => { this.noteText = q.userNote ?? ''; this.showNoteDialog = true; })
      MenuItem({ startIcon: $r('sys.media.ohos_ic_public_delete'), content: '删除题目' })
        .onClick(() => { this.showDeleteConfirm = true; })
        .contentFontColor($r('app.color.danger'))
    }
  }

  @Builder StatChip(text: string, color: string) {
    Text(text)
      .fontSize(13).fontColor(color)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(color + '1A')
      .borderRadius(20).margin({ right: 8 })
  }

  @Builder FilterChip(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(active ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(active ? $r('app.color.primary') : $r('app.color.bg_card'))
      .borderRadius(20)
      .margin({ right: 8 })
      .onClick(onTap)
  }

  private formatRate(rate: number | undefined): string {
    if (!rate || isNaN(rate)) return '--%';
    return Math.round(rate * 100) + '%';
  }
}
