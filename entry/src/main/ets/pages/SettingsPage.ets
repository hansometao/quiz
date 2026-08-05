import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { getContext } from '@ohos.arkui.UIContext';
import { BackupService } from '../service/BackupService';
import { DatabaseService } from '../service/DatabaseService';

const PREF_NAME = 'quiz_settings';

@Component
export struct SettingsPage {
  @State fontSize: number = 1;   // 0=小 1=中 2=大
  @State soundEnabled: boolean = true;
  @State vibrationEnabled: boolean = true;
  @State autoRemoveThreshold: number = 3;
  @State showConfirmClear: boolean = false;
  @State appVersion: string = '1.0.0';
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  @State exporting: boolean = false;
  @State importing: boolean = false;
  @State exportingMistakes: boolean = false;
  @State clearingHistory: boolean = false;

  private pref: preferences.Preferences | null = null;
  private backup: BackupService = BackupService.getInstance();
  // 标记页面是否已销毁，所有 await 后必须检查，避免在销毁组件上写状态
  private isAlive: boolean = true;
  // save 防抖计时器：Slider 拖动时高频触发 onChange，防抖避免每 tick 都 flush 持久化
  private saveDebounceTimer: number = -1;

  aboutToAppear() {
    this.loadPrefs();
  }

  aboutToDisappear() {
    this.isAlive = false;
  }

  async loadPrefs() {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      this.pref = await preferences.getPreferences(ctx, PREF_NAME);
      if (!this.isAlive) return;
      this.fontSize            = await this.pref.get('fontSize',          1)     as number;
      this.soundEnabled        = await this.pref.get('soundEnabled',      true)  as boolean;
      this.vibrationEnabled    = await this.pref.get('vibrationEnabled',  true)  as boolean;
      if (!this.isAlive) return;
      // 阈值统一由 DatabaseService 管理（键 'auto_remove_threshold'），避免双键分叉
      this.autoRemoveThreshold = DatabaseService.getInstance().autoRemoveThreshold;
    } catch (e) {
      if (!this.isAlive) return;
      console.error('加载设置失败', e);
    }
  }

  async save(key: string, value: preferences.ValueType) {
    if (!this.pref) return;
    await this.pref.put(key, value);
    await this.pref.flush();
  }

  /** 防抖持久化：Slider 拖动时高频触发，延迟 400ms 合并写入，避免 I/O 风暴 */
  saveDebounced(key: string, value: preferences.ValueType): void {
    if (this.saveDebounceTimer >= 0) clearTimeout(this.saveDebounceTimer);
    this.saveDebounceTimer = setTimeout(() => {
      this.saveDebounceTimer = -1;
      this.save(key, value);
    }, 400);
  }

  showMsg(msg: string) {
    this.toastMsg = msg;
    this.showToast = true;
    setTimeout(() => { if (this.isAlive) this.showToast = false; }, 2500);
  }

  // ── 导出备份 ──
  async doExport() {
    if (this.exporting) return;
    this.exporting = true;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const path = await this.backup.exportBackup(ctx);
      if (!this.isAlive) return;
      await this.backup.shareFile(ctx, path);
      if (!this.isAlive) return;
      this.showMsg('备份已导出，请通过分享保存到安全位置');
    } catch (e) {
      if (!this.isAlive) return;
      this.showMsg('导出失败：' + (e as Error).message);
    } finally {
      if (this.isAlive) this.exporting = false;
    }
  }

  // ── 导入还原 ──
  async doImport() {
    if (this.importing) return;
    this.importing = true;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const result = await this.backup.importBackup(ctx);
      if (!this.isAlive) return;
      this.showMsg(result.message);
    } catch (e) {
      if (!this.isAlive) return;
      this.showMsg('还原失败：' + (e as Error).message);
    } finally {
      if (this.isAlive) this.importing = false;
    }
  }

  // ── 导出错题 CSV ──
  async doExportMistakes() {
    if (this.exportingMistakes) return;
    this.exportingMistakes = true;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const path = await this.backup.exportMistakesCSV(ctx);
      if (!this.isAlive) return;
      await this.backup.shareFile(ctx, path);
      if (!this.isAlive) return;
      this.showMsg('错题已导出为 CSV，请通过分享保存');
    } catch (e) {
      if (!this.isAlive) return;
      this.showMsg('导出失败：' + (e as Error).message);
    } finally {
      if (this.isAlive) this.exportingMistakes = false;
    }
  }

  // ── 清除记录 ──
  async doClearHistory() {
    if (this.clearingHistory) return;
    this.clearingHistory = true;
    try {
      await DatabaseService.getInstance().backup.clearAllHistory();
      if (!this.isAlive) return;
      this.showConfirmClear = false;
      this.showMsg('答题记录已清除');
    } catch (e) {
      if (!this.isAlive) return;
      this.showMsg('清除失败：' + (e as Error).message);
    } finally {
      if (this.isAlive) this.clearingHistory = false;
    }
  }

  build() {
    Stack() {
      Column() {
        Text('设置').fontSize(22).fontWeight(FontWeight.Bold)
          .padding({ left: 16, top: 16, bottom: 12 }).alignSelf(ItemAlign.Start)

        Scroll() {
          Column() {
            // ── 外观 ──
            this.GroupTitle('外观')
            Column() {
              Row() {
                Text('字体大小').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
                Text(['小', '中', '大'][this.fontSize]).fontSize(14).fontColor($r('app.color.primary'))
              }
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })
              Slider({ value: this.fontSize, min: 0, max: 2, step: 1 })
                .padding({ left: 16, right: 16, bottom: 12 })
                .onChange((v) => { this.fontSize = Math.round(v); this.saveDebounced('fontSize', Math.round(v)); })
            }
            .backgroundColor($r('app.color.bg_card')).borderRadius(10).margin({ bottom: 8 })

            // ── 反馈 ──
            this.GroupTitle('反馈')
            this.SwitchRow('答题音效', this.soundEnabled, (v: boolean) => {
              this.soundEnabled = v; this.save('soundEnabled', v);
            })
            this.SwitchRow('振动反馈', this.vibrationEnabled, (v: boolean) => {
              this.vibrationEnabled = v; this.save('vibrationEnabled', v);
            })

            // ── 学习 ──
            this.GroupTitle('学习')
            Column() {
              Row() {
                Text('错题自动移出阈值').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
                Text('连续正确 ' + this.autoRemoveThreshold + ' 次').fontSize(13).fontColor($r('app.color.primary'))
              }
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })
              Slider({ value: this.autoRemoveThreshold, min: 1, max: 10, step: 1 })
                .padding({ left: 16, right: 16, bottom: 12 })
                .onChange((v) => {
                  this.autoRemoveThreshold = Math.round(v);
                })
                .onSubmit(() => {
                  // 拖动结束时才持久化，避免拖动过程中每 tick 都写 DB
                  DatabaseService.getInstance().syncAutoRemoveThreshold(this.autoRemoveThreshold);
                })
            }
            .backgroundColor($r('app.color.bg_card')).borderRadius(10).margin({ bottom: 8 })

            // ── 数据备份 ──
            this.GroupTitle('数据备份与还原')
            Column() {
              // 导出备份
              Row() {
                Column() {
                  Text('导出备份').fontSize(15).fontColor($r('app.color.text_primary'))
                  Text('将所有题库、题目和记录打包导出').fontSize(12).fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.exporting) {
                  LoadingProgress().width(20).height(20).color($r('app.color.primary'))
                } else {
                  Text('导出').fontSize(14).fontColor($r('app.color.primary'))
                }
              }
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => this.doExport())

              Divider().color($r('app.color.border')).margin({ left: 16 })

              // 导入还原
              Row() {
                Column() {
                  Text('导入还原').fontSize(15).fontColor($r('app.color.text_primary'))
                  Text('从备份文件中还原数据（覆盖当前数据）').fontSize(12).fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.importing) {
                  LoadingProgress().width(20).height(20).color($r('app.color.primary'))
                } else {
                  Text('导入').fontSize(14).fontColor($r('app.color.primary'))
                }
              }
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => this.doImport())

              Divider().color($r('app.color.border')).margin({ left: 16 })

              // 导出错题 CSV
              Row() {
                Column() {
                  Text('导出错题').fontSize(15).fontColor($r('app.color.text_primary'))
                  Text('将错题本导出为 CSV（可用 Excel 打开）').fontSize(12).fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('导出 CSV').fontSize(14).fontColor($r('app.color.primary'))
              }
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => this.doExportMistakes())
            }
            .backgroundColor($r('app.color.bg_card')).borderRadius(10).margin({ bottom: 8 })

            // ── 数据管理 ──
            this.GroupTitle('数据管理')
            Column() {
              Row() {
                Column() {
                  Text('清除答题记录').fontSize(15).fontColor($r('app.color.danger'))
                  Text('仅清除记录，保留题库和题目，不可恢复').fontSize(12).fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => this.showConfirmClear = true)
            }
            .backgroundColor($r('app.color.bg_card')).borderRadius(10).margin({ bottom: 8 })

            // ── 关于 ──
            this.GroupTitle('关于')
            Column() {
              this.InfoRow('应用版本', this.appVersion)
              Divider().color($r('app.color.border')).margin({ left: 16 })
              this.InfoRow('开发技术', 'ArkTS + ArkUI')
              Divider().color($r('app.color.border')).margin({ left: 16 })
              this.InfoRow('数据库', 'RelationalStore (SQLite)')
              Divider().color($r('app.color.border')).margin({ left: 16 })
              this.InfoRow('目标平台', 'HarmonyOS NEXT API 12+')
            }
            .backgroundColor($r('app.color.bg_card')).borderRadius(10).margin({ bottom: 8 })

            Blank().height(40)
          }
          .padding(16)
        }
        .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor($r('app.color.bg_primary'))

      // ── 清除记录确认弹窗 ──
      if (this.showConfirmClear) {
        Stack() {
          Column()
            .width('100%').height('100%').backgroundColor('#80000000')
            .onClick(() => this.showConfirmClear = false)

          Column() {
            Text('⚠️ 确认清除').fontSize(17).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
            Text('此操作将清除所有答题记录和统计数据（含错题本），题库数据不受影响，且不可恢复。建议先导出备份。')
              .fontSize(14).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center).margin({ bottom: 20 })
            Row() {
              Button('取消').layoutWeight(1).height(44).fontSize(15).borderRadius(10)
                .backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary'))
                .border({ width: 1, color: $r('app.color.border') })
                .onClick(() => this.showConfirmClear = false)
              Blank().width(12)
              Button('确认清除').layoutWeight(1).height(44).fontSize(15).borderRadius(10)
                .backgroundColor($r('app.color.danger')).fontColor(Color.White)
                .onClick(() => this.doClearHistory())
            }
          }
          .padding(24)
          .backgroundColor($r('app.color.bg_card')).borderRadius(16)
          .width('85%')
          .position({ x: '7.5%', y: '30%' })
        }
        .width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(100)
      }

      // ── Toast 提示 ──
      if (this.showToast) {
        Text(this.toastMsg)
          .fontSize(14).fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          .backgroundColor('#CC333333')
          .borderRadius(24)
          .position({ x: '10%', y: '80%' })
          .width('80%')
          .textAlign(TextAlign.Center)
          .zIndex(200)
      }
    }
    .width('100%').height('100%')
  }

  @Builder GroupTitle(title: string) {
    Text(title)
      .fontSize(13).fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 4, bottom: 6, top: 12 })
      .alignSelf(ItemAlign.Start)
  }

  @Builder SwitchRow(label: string, value: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(label).fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value }).onChange(onChange)
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.bg_card')).borderRadius(10).margin({ bottom: 8 })
  }

  @Builder InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).layoutWeight(1)
      Text(value).fontSize(14).fontColor($r('app.color.text_primary'))
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
}
