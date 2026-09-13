// @ohos.file.fs 测试桩：覆盖 BackupService（异步 API）与 ZipUtils（同步 API）导入的成员。
// 行为经 fsState 注入：stat 大小 / accessSync 结果 / copyFile 记录 / 已删除路径记录。
const fsState = {
  statSize: 0,
  accessExists: false,
  copied: [] as string[],
  deleted: [] as string[],
};

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
  accessSync: () => fsState.accessExists,
  // 同步 API（ZipUtils 使用；行为级测试前先按需扩展）
  openSync: () => ({ fd: 1 }),
  closeSync: () => {},
  readSync: () => 0,
  statSync: () => ({ size: 0 }),
  lstatSync: () => ({ isSymbolicLink: () => false, size: 0 }),
  listFileSync: () => [] as string[],
  mkdirSync: () => {},
  rmdirSync: () => {},
};
export default fs;
export { fsState };
