import router from '@ohos.router';
import picker from '@ohos.file.picker';
import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
import { ExcelParser } from '../service/ExcelParser';
import { DatabaseService } from '../service/DatabaseService';
import { LoadingOverlay } from '../components/CommonComponents';
import { getContext } from '@ohos.arkui.UIContext';
import { Question } from '../model/Models';

@Entry
@Component
struct ImportPage {
  @State loading: boolean = false;
  @State loadingMsg: string = '';
  @State result: ImportResult | null = null;
  @State editName: string = '';
  // 标记页面是否已销毁，所有 await 后必须检查，避免在销毁组件上写状态
  private isAlive: boolean = true;

  aboutToDisappear() {
    this.isAlive = false;
  }

  build() {
    Stack() {
      Column() {
        // 导航栏
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('←').fontSize(18).fontColor($r('app.color.text_primary'))
          }
          .width(36).height(36).backgroundColor(Color.Transparent)
          .onClick(() => router.back())

          Text('导入题库').fontSize(18).fontWeight(FontWeight.Bold).margin({ left: 8 })
        }
        .width('100%').padding(16).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            // 说明卡片
            Column() {
              Text('📋 导入说明').fontSize(15).fontWeight(FontWeight.Bold).margin({ bottom: 10 })
              this.TipRow('支持 .xlsx / .xls 格式的 Excel 文件')
              this.TipRow('第一行为表头，后续行为题目数据')
              this.TipRow('必填字段：题目、题型、答案')
              this.TipRow('选填字段：选项A~E、解析、分类、难度、分值')
            }
            .width('100%').padding(16)
            .backgroundColor($r('app.color.bg_card')).borderRadius(12)
            .margin({ bottom: 16 })

            // 选择文件按钮
            Button('选择 Excel 文件')
              .width('100%').height(52)
              .fontSize(16).borderRadius(12)
              .backgroundColor($r('app.color.primary')).fontColor(Color.White)
              .enabled(!this.loading)
              .onClick(() => this.pickFile())
              .margin({ bottom: 16 })

            // 结果展示
            if (this.result) {
              this.ResultCard()
            }
          }
          .padding(16)
        }
        .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      LoadingOverlay({ visible: this.loading, message: this.loadingMsg })
    }
  }

  @Builder TipRow(text: string) {
    Row() {
      Text('•').fontSize(13).fontColor($r('app.color.primary')).margin({ right: 6 })
      Text(text).fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
    }.margin({ bottom: 4 })
  }

  @Builder ResultCard() {
    Column() {
      Text('导入结果').fontSize(15).fontWeight(FontWeight.Bold).margin({ bottom: 12 })

      // 题库名称编辑
      Row() {
        Text('题库名称：').fontSize(14).fontColor($r('app.color.text_secondary')).width(80)
        TextInput({ text: this.editName })
          .layoutWeight(1).height(40).fontSize(14).borderRadius(8)
          .onChange((v) => this.editName = v)
      }
      .margin({ bottom: 12 })

      Row() {
        this.StatBadge('成功', String(this.result!.successCount), $r('app.color.success'))
        this.StatBadge('跳过', String(this.result!.skippedCount), $r('app.color.warning'))
        this.StatBadge('错误', String(this.result!.errorCount), $r('app.color.danger'))
      }
      .width('100%').justifyContent(FlexAlign.SpaceAround).margin({ bottom: 12 })

      if (this.result!.errors.length > 0) {
        Column() {
          Text('⚠️ 以下行有问题：').fontSize(13).fontColor($r('app.color.warning')).margin({ bottom: 6 })
          ForEach(this.result!.errors.slice(0, 10), (err: string) => {
            Text('• ' + err).fontSize(12).fontColor($r('app.color.text_secondary')).margin({ bottom: 3 })
          }, (err: string, idx: number) => idx.toString())
          if (this.result!.errors.length > 10) {
            Text(`还有 ${this.result!.errors.length - 10} 个问题...`).fontSize(12).fontColor($r('app.color.text_tertiary'))
          }
        }
        .width('100%').padding(10).backgroundColor($r('app.color.warning_tip_bg')).borderRadius(8).margin({ bottom: 12 })
      }

      if (this.result!.successCount > 0) {
        Button('保存题库')
          .width('100%').height(48)
          .fontSize(16).borderRadius(12)
          .backgroundColor($r('app.color.primary')).fontColor(Color.White)
          .onClick(() => this.saveBank())
      }
    }
    .width('100%').padding(16)
    .backgroundColor($r('app.color.bg_card')).borderRadius(12)
  }

  @Builder StatBadge(label: string, value: string, color: ResourceColor) {
    Column() {
      Text(value).fontSize(22).fontWeight(FontWeight.Bold).fontColor(color)
      Text(label).fontSize(12).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
    }
  }

  private async pickFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.xlsx', '.xls'],
      });
      if (!result || result.length === 0) return;

      const filePath = result[0];
      await this.parseFile(filePath);
    } catch (e) {
      console.error('选文件失败', e);
    }
  }

  private async parseFile(filePath: string): Promise<void> {
    this.loading = true;
    this.loadingMsg = '正在解析 Excel...';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const tmpDir = `${context.cacheDir}/xlsx_tmp_${Date.now()}`;
      const parser = new ExcelParser();
      const parseResult = await parser.parse(filePath, tmpDir);
      if (!this.isAlive) return;

      this.editName = parseResult.bankName || '未命名题库';
      this.result = {
        filePath,
        questions: parseResult.questions,
        successCount: parseResult.questions.length,
        skippedCount: parseResult.skipped,
        errorCount: parseResult.errors.length,
        errors: parseResult.errors,
      };
    } catch (e) {
      if (!this.isAlive) return;
      console.error('解析失败', e);
      this.result = null;
      promptAction.showToast({ message: '解析失败：' + ((e as Error).message || '未知错误') });
    }
    if (this.isAlive) this.loading = false;
  }

  private saving: boolean = false;  // 防重入

  private async saveBank(): Promise<void> {
    if (!this.result || this.result.questions.length === 0) return;
    if (this.saving) return;  // 防止快速双击重复导入
    this.saving = true;
    this.loading = true;
    this.loadingMsg = `正在导入 ${this.result.successCount} 道题...`;
    const db = DatabaseService.getInstance();
    let bankId: number | null = null;
    try {
      bankId = await db.banks.insert(this.editName, '', this.result.filePath);
      await db.questions.batchInsert(bankId, this.result.questions);
      await db.banks.refreshCount(bankId);
      if (!this.isAlive) return;
      this.loading = false;
      router.back();
    } catch (e) {
      console.error('保存失败', e);
      // 失败回滚：删除已创建的孤儿题库，避免半成品残留导致重复导入
      if (bankId !== null) {
        try { await db.banks.delete(bankId); } catch {}
      }
      if (!this.isAlive) return;
      this.loading = false;
      promptAction.showToast({ message: '保存失败：' + ((e as Error).message || '请重试') });
    } finally {
      this.saving = false;
    }
  }
}

interface ImportResult {
  filePath: string;
  questions: Partial<Question>[];
  successCount: number;
  skippedCount: number;
  errorCount: number;
  errors: string[];
}
