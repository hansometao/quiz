/**
 * app.ets - 全局应用入口
 *
 * 在 HarmonyOS NEXT 中用于：
 * - 全局生命周期回调
 * - 注册全局错误处理
 */

import errorManager from '@ohos.app.ability.errorManager';
import hilog from '@ohos.hilog';

const TAG = 'app.ets';

/**
 * 应用全局配置
 */
export default {
  onCreate(): void {
    // 注册全局错误处理：捕获未处理的异常和 Promise rejection，统一记录日志
    try {
      errorManager.on('error', (err) => {
        hilog.error(0x0000, TAG, '全局异常: name=%{public}s, message=%{public}s, stack=%{public}s',
          err.name ?? '', err.message ?? '', err.stack ?? '');
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, '注册 errorManager.on(error) 失败: %{public}s', JSON.stringify(e));
    }
    try {
      errorManager.on('unhandledRejection', (err) => {
        hilog.error(0x0000, TAG, '未处理的 Promise 拒绝: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, '注册 errorManager.on(unhandledRejection) 失败: %{public}s', JSON.stringify(e));
    }
  },
};
