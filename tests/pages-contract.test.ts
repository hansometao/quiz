import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

// ArkUI 页面（@Entry/@Component struct）无法在 Node 下实例化，
// 用源码契约测试守护"页面引用的成员必须有定义"这类编译级错误。
// 背景：HistoryDetailPage.ets 曾引用 this.wrongCount 但无定义，
// ArkTS 编译直接失败（H-1）。

const PAGES = resolve(__dirname, '../entry/src/main/ets/pages');

function src(name: string): string {
  return readFileSync(resolve(PAGES, name), 'utf-8');
}

describe('页面源码契约', () => {
  it('HistoryDetailPage 引用的 wrongCount 必须有定义（H-1 回归防护）', () => {
    const s = src('HistoryDetailPage.ets');
    const references = (s.match(/this\.wrongCount/g) ?? []).length;
    if (references > 0) {
      // 需存在 getter 或字段定义：get wrongCount / wrongCount[:=]
      const defined = /get\s+wrongCount|wrongCount\s*[:=]/.test(s);
      expect(defined, `HistoryDetailPage 引用了 this.wrongCount ${references} 次但未定义`).toBe(true);
    }
  });

  it('SettingsPage 阈值 Slider 的修改必须有持久化路径（M-15 回归防护）', () => {
    const s = src('SettingsPage.ets');
    // autoRemoveThreshold 的 onChange 中必须出现持久化调用（syncAutoRemoveThreshold
    // 或 saveDebounced）；只挂在 onSubmit 不够——拖动后直接返回页面 onSubmit
    // 不会触发，修改会静默丢失
    const sliderBlock = s.slice(s.indexOf('错题自动移出阈值'), s.indexOf('数据备份'));
    expect(sliderBlock).toContain('autoRemoveThreshold');
    // 只取 onChange 代码块（截止到 .onSubmit 之前），排除 onSubmit 里的持久化
    const onChangePart = sliderBlock.split('.onSubmit')[0];
    expect(
      /syncAutoRemoveThreshold|saveDebounced/.test(onChangePart),
      '阈值 Slider onChange 未接持久化（仅 onSubmit 持久化），拖动后直接返回会静默丢失修改'
    ).toBe(true);
  });
});
