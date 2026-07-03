/**
 * app.ets - 全局应用入口
 *
 * 在 HarmonyOS NEXT 中用于：
 * - 定义全局主题颜色（配合深色模式）
 * - 注册全局自定义字体
 * - 全局生命周期回调
 *
 * 注意：当前项目的颜色通过 resources/base/element/color.json 管理，
 * app.ets 中的颜色设置会与资源文件合并使用。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 应用全局配置（可选）
 * 若不需要全局深色模式支持，可保留为空。
 */
export default {
  onCreate(): void {
    // 应用冷启动时的初始化逻辑
    // 可用于：注册全局错误处理、初始化公共组件等
  },
};
