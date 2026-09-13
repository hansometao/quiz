// @ohos.file.fs 测试桩：覆盖 BackupService（异步 API）与 ZipUtils/ExcelParser（同步 API）。
// 注入方式：
//   fsState.statSize     — 异步 stat 返回的字节数（BackupService 大小校验链用）
//   fsState.files        — 路径 → 文本内容，驱动同步 readTextFile 全链
//                          （openSync 分配 fd → statSync 返回字节数 → readSync 填充 buf）
//   fsState.accessExists — 未登记路径的 accessSync 兜底行为（BackupService 用）
const fsState = {
  statSize: 0,
  accessExists: false,
  copied: [] as string[],
  deleted: [] as string[],
  files: {} as Record<string, string>,
};

let nextFd = 1;
const fdToPath = new Map<number, string>();

const byteLength = (s: string): number => new TextEncoder().encode(s).length;

/** 按路径解析注入内容：精确匹配优先，其次后缀匹配（键以 '/' 开头表示后缀，
 *  用于随机临时目录名场景，如 createTempDir 生成的 /tmp/quiz_parse_<时间戳>） */
function resolveFile(path: string): string | undefined {
  const exact = fsState.files[path];
  if (exact !== undefined) return exact;
  for (const [key, val] of Object.entries(fsState.files)) {
    if (key.startsWith('/') && path.endsWith(key)) return val;
  }
  return undefined;
}

const fs = {
  OpenMode: { READ_ONLY: 0o0, READ_WRITE: 0o2, CREATE: 0o100, TRUNC: 0o1000 },
  // 异步 API（BackupService 使用）
  open: async () => ({ fd: 1 }),
  close: async () => {},
  read: async () => ({ bytesRead: 0 }),
  write: async () => 0,
  copyFile: async (src: string, dst: string) => { fsState.copied.push(`${src}->${dst}`); },
  stat: async () => ({ size: fsState.statSize }),
  unlinkSync: (p: string) => { fsState.deleted.push(p); },
  accessSync: (path: string) => {
    // 已登记内容（精确或后缀匹配）的路径视为存在；未登记则按 accessExists 兜底，默认抛 ENOENT
    if (resolveFile(path) !== undefined) return;
    if (fsState.accessExists) return;
    throw new Error(`ENOENT: ${path}`);
  },
  // 同步 API（ZipUtils / ExcelParser 使用）
  openSync: (path: string, _mode: number) => {
    const fd = nextFd++;
    fdToPath.set(fd, path);
    return { fd };
  },
  closeSync: () => {},
  statSync: (path: string) => {
    const content = resolveFile(path);
    return { size: content !== undefined ? byteLength(content) : 0 };
  },
  readSync: (fd: number, buf: ArrayBuffer) => {
    const path = fdToPath.get(fd);
    const content = path !== undefined ? resolveFile(path) : undefined;
    if (content === undefined) return 0;
    const bytes = new TextEncoder().encode(content);
    if (bytes.length > buf.byteLength) return 0;
    new Uint8Array(buf).set(bytes);
    return bytes.length;
  },
  // 目录/元数据类：默认非符号链接、非目录、无子项（zip bomb 扫描与 calcDirSize 因此得 0 体积）。
  // 注意 lstatSync 必须返回 isDirectory 方法——ZipUtils.rmdir 会调用它，
  // 缺方法会抛 TypeError 被 try/catch 吞掉，导致临时目录清理静默失败
  lstatSync: () => ({ isSymbolicLink: () => false, isDirectory: () => false, size: 0 }),
  listFileSync: () => [] as string[],
  mkdirSync: () => {},
  rmdirSync: (p: string) => { fsState.deleted.push(p); },
};
export default fs;
export { fsState };
