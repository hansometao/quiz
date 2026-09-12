import { describe, it, expect } from 'vitest';
import { BackupService } from '../entry/src/main/ets/service/BackupService';

// csvEscape 为私有方法，经原型访问做行为级测试（不触发 HarmonyOS 运行时）
const csvEscape = (BackupService.prototype as unknown as {
  csvEscape: (s: string) => string;
}).csvEscape;

describe('BackupService.csvEscape', () => {
  it('普通文本原样输出', () => {
    expect(csvEscape('普通文本')).toBe('普通文本');
  });

  it('空值返回空串', () => {
    expect(csvEscape('')).toBe('');
  });

  it('含逗号/引号/换行时包裹双引号并转义引号', () => {
    expect(csvEscape('a,b')).toBe('"a,b"');
    expect(csvEscape('他说"你好"')).toBe('"他说""你好"""');
    expect(csvEscape('line1\nline2')).toBe('"line1\nline2"');
  });

  it('公式注入防护：= + - @ 开头加单引号前缀', () => {
    expect(csvEscape('=cmd()')).toBe("'=cmd()");
    expect(csvEscape('+1')).toBe("'+1");
    expect(csvEscape('@SUM(A1)')).toBe("'@SUM(A1)");
    expect(csvEscape('-5')).toBe("'-5"); // 已知 tradeoff：负数变文本
  });
});
