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
 *   3. 用 BreakpointUtils.columns(bp) 等工具方法决定列数/宽度
 */

import mediaQuery from '@ohos.mediaquery';
import window from '@ohos.window';

/** 断点常量 */
export class Breakpoint {
  static readonly SM = 'sm';
  static readonly MD = 'md';
  static readonly LG = 'lg';
}

/** 断点系统（单例，全局注册一次） */
export class BreakpointSystem {
  private static smListener?: mediaQuery.MediaQueryListener;
  private static mdListener?: mediaQuery.MediaQueryListener;
  private static lgListener?: mediaQuery.MediaQueryListener;
  // 保存回调引用，确保 off 能正确移除
  private static smCb?: (result: mediaQuery.MediaQueryResult) => void;
  private static mdCb?: (result: mediaQuery.MediaQueryResult) => void;
  private static lgCb?: (result: mediaQuery.MediaQueryResult) => void;

  static register(windowStage: window.WindowStage): void {
    // 更新 AppStorage 中的 'breakpoint' 键
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
    } catch {}

    // 注册媒体查询监听器
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
    }
    if (BreakpointSystem.mdListener && BreakpointSystem.mdCb) {
      BreakpointSystem.mdListener.off('change', BreakpointSystem.mdCb);
    }
    if (BreakpointSystem.lgListener && BreakpointSystem.lgCb) {
      BreakpointSystem.lgListener.off('change', BreakpointSystem.lgCb);
    }
  }
}

/** 断点工具函数 */
export class BreakpointUtils {
  /** 题库卡片列数：sm=1, md=2, lg=3 */
  static bankColumns(bp: string): number {
    if (bp === Breakpoint.LG) return 3;
    if (bp === Breakpoint.MD) return 2;
    return 1;
  }

  /** 历史/分析列表列数：sm=1, md=2, lg=2 */
  static listColumns(bp: string): number {
    return bp === Breakpoint.SM ? 1 : 2;
  }

  /** 是否使用双栏（主从）布局 */
  static isDualPane(bp: string): boolean {
    return bp === Breakpoint.LG;
  }

  /** 侧边栏宽度（双栏模式左侧） */
  static sideWidth(bp: string): string {
    return bp === Breakpoint.LG ? '320vp' : '0';
  }

  /** 内容区 padding */
  static contentPadding(bp: string): number {
    if (bp === Breakpoint.LG) return 32;
    if (bp === Breakpoint.MD) return 24;
    return 16;
  }

  /** 响应式值选择器 */
  static value<T>(bp: string, sm: T, md: T, lg: T): T {
    if (bp === Breakpoint.LG) return lg;
    if (bp === Breakpoint.MD) return md;
    return sm;
  }
}
