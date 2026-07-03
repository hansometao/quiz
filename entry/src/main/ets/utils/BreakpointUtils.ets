/**
 * BreakpointUtils.ets
 * 响应式布局工具 —— 根据屏幕宽度自动切换断点
 *
 * 断点规则（参考 HarmonyOS 官方规范）：
 *   sm  < 600vp   手机竖屏
 *   md  600~840vp 手机横屏 / 小平板
 *   lg  > 840vp   大平板 / 折叠屏展开
 *
 * 使用方式：
 *   1. 在根 Ability 初始化 BreakpointSystem.register(windowStage)
 *   2. 组件内用 @StorageProp('breakpoint') bp: string = 'sm' 订阅断点变化
 */

import mediaQuery from '@ohos.mediaquery';
import window from '@ohos.window';
import hilog from '@ohos.hilog';

const TAG = 'BreakpointUtils';

/** 断点常量 */
export class Breakpoint {
  static readonly SM = 'sm';
  static readonly MD = 'md';
  static readonly LG = 'lg';
}

/** 断点系统（全局注册一次；重复调用会先注销旧监听器，避免泄漏） */
export class BreakpointSystem {
  private static smListener?: mediaQuery.MediaQueryListener;
  private static mdListener?: mediaQuery.MediaQueryListener;
  private static lgListener?: mediaQuery.MediaQueryListener;
  private static smCb?: (result: mediaQuery.MediaQueryResult) => void;
  private static mdCb?: (result: mediaQuery.MediaQueryResult) => void;
  private static lgCb?: (result: mediaQuery.MediaQueryResult) => void;

  static register(windowStage: window.WindowStage): void {
    // 防重复注册：先注销旧监听器，避免 Ability 重建导致监听器累积泄漏
    BreakpointSystem.unregister();

    const updateBp = (bp: string) => {
      AppStorage.setOrCreate('breakpoint', bp);
    };

    // 先读一次当前窗口宽度确定初始断点
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const props = mainWindow.getWindowProperties();
      const vp = px2vp(props.windowRect.width);
      if (vp < 600)      updateBp(Breakpoint.SM);
      else if (vp < 840) updateBp(Breakpoint.MD);
      else               updateBp(Breakpoint.LG);
    } catch (err) {
      hilog.warn(0x0000, TAG, `read initial breakpoint failed: ${JSON.stringify(err)}`);
    }

    BreakpointSystem.smListener = mediaQuery.matchMediaSync('(width < 600vp)');
    BreakpointSystem.mdListener = mediaQuery.matchMediaSync('(600vp <= width < 840vp)');
    BreakpointSystem.lgListener = mediaQuery.matchMediaSync('(width >= 840vp)');

    BreakpointSystem.smCb = (result: mediaQuery.MediaQueryResult) => { if (result.matches) updateBp(Breakpoint.SM); };
    BreakpointSystem.mdCb = (result: mediaQuery.MediaQueryResult) => { if (result.matches) updateBp(Breakpoint.MD); };
    BreakpointSystem.lgCb = (result: mediaQuery.MediaQueryResult) => { if (result.matches) updateBp(Breakpoint.LG); };

    BreakpointSystem.smListener.on('change', BreakpointSystem.smCb);
    BreakpointSystem.mdListener.on('change', BreakpointSystem.mdCb);
    BreakpointSystem.lgListener.on('change', BreakpointSystem.lgCb);
  }

  static unregister(): void {
    if (BreakpointSystem.smListener && BreakpointSystem.smCb) {
      BreakpointSystem.smListener.off('change', BreakpointSystem.smCb);
      BreakpointSystem.smListener = undefined;
      BreakpointSystem.smCb = undefined;
    }
    if (BreakpointSystem.mdListener && BreakpointSystem.mdCb) {
      BreakpointSystem.mdListener.off('change', BreakpointSystem.mdCb);
      BreakpointSystem.mdListener = undefined;
      BreakpointSystem.mdCb = undefined;
    }
    if (BreakpointSystem.lgListener && BreakpointSystem.lgCb) {
      BreakpointSystem.lgListener.off('change', BreakpointSystem.lgCb);
      BreakpointSystem.lgListener = undefined;
      BreakpointSystem.lgCb = undefined;
    }
  }
}
