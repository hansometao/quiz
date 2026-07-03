import UIAbility from '@ohos.app.ability.UIAbility';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { DatabaseService } from '../service/DatabaseService';
import { BreakpointSystem } from '../utils/BreakpointUtils';

const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    // 初始化数据库
    DatabaseService.getInstance().init(this.context).then(() => {
      hilog.info(0x0000, TAG, '数据库初始化完成');
    }).catch((err: Error) => {
      hilog.error(0x0000, TAG, '数据库初始化失败: %{public}s', err.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate');
    // 注册响应式断点监听（平板/折叠屏自适应）
    BreakpointSystem.register(windowStage);
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
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
