import UIAbility from '@ohos.app.ability.UIAbility';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import preferences from '@ohos.data.preferences';
import { DatabaseService } from '../service/DatabaseService';
import { BreakpointSystem } from '../utils/BreakpointUtils';

const TAG = 'EntryAbility';
const FONT_PREF_NAME = 'quiz_settings';
const FONT_PREF_KEY = 'fontSize';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    // 初始化数据库
    DatabaseService.getInstance().init(this.context).then(() => {
      hilog.info(0x0000, TAG, '数据库初始化完成');
    }).catch((err: Error) => {
      hilog.error(0x0000, TAG, '数据库初始化失败: %{public}s', err.message);
    });
    // M-14：冷启动恢复字体档位到 AppStorage（QuestionCard 经 @StorageProp 消费）。
    // 异步加载，加载完成前组件用默认档位 1（中），完成后自动刷新
    preferences.getPreferences(this.context, FONT_PREF_NAME).then((pref) => {
      return pref.get(FONT_PREF_KEY, 1) as Promise<number>;
    }).then((scale) => {
      AppStorage.setOrCreate('fontScale', scale);
    }).catch((err: Error) => {
      hilog.error(0x0000, TAG, '恢复字体设置失败: %{public}s', err.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate');
    // 注册响应式断点监听（平板/折叠屏自适应）
    BreakpointSystem.register(windowStage);
    windowStage.loadContent('pages/Index', (err) => {
      if (err && err.code) {
        hilog.error(0x0000, TAG, '加载页面失败: %{public}s', JSON.stringify(err));
      }
    });
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy');
    DatabaseService.getInstance().close();
    BreakpointSystem.unregister();
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'onBackground');
  }
}
