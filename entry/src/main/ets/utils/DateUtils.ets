/**
 * 日期工具函数
 */
export class DateUtils {
  /** Unix 时间戳（秒）转 "YYYY-MM-DD" */
  static formatDate(unixSec: number): string {
    if (!unixSec) return '';
    const d = new Date(unixSec * 1000);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  /** Unix 时间戳（秒）转 "YYYY-MM-DD HH:mm" */
  static formatDateTime(unixSec: number): string {
    if (!unixSec) return '';
    const d = new Date(unixSec * 1000);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  /** 秒数转 "mm:ss" */
  static formatDuration(sec: number): string {
    if (!sec || sec < 0) return '00:00';
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) return `${pad(h)}:${pad(m)}:${pad(s)}`;
    return `${pad(m)}:${pad(s)}`;
  }

  /** 秒数转可读文字 "X小时X分X秒" */
  static formatDurationLabel(sec: number): string {
    if (!sec || sec < 0) return '0秒';
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    let label = '';
    if (h > 0) label += h + '小时';
    if (m > 0) label += m + '分';
    if (s > 0 || !label) label += s + '秒';
    return label;
  }

  /** 获取今天的日期字符串 */
  static today(): string {
    const d = new Date();
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  /** 当前 Unix 时间戳（秒） */
  static now(): number {
    return Math.floor(Date.now() / 1000);
  }

  /** 毫秒转可读字符串，用于展示每题用时 */
  static formatMs(ms: number): string {
    if (!ms || ms <= 0) return '—';
    if (ms < 1000) return ms + 'ms';
    const sec = Math.round(ms / 1000);
    if (sec < 60) return sec + 's';
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}m${pad(s)}s`;
  }
}

function pad(n: number): string {
  return n < 10 ? '0' + n : String(n);
}
