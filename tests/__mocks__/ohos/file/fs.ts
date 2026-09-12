// @ohos.file.fs 测试桩：仅覆盖被导入的成员
const fs = {
  OpenMode: { READ_ONLY: 0o0, READ_WRITE: 0o2, CREATE: 0o100, TRUNC: 0o1000 },
  open: async () => ({ fd: 0 }),
  close: async () => {},
  read: async () => ({ bytesRead: 0 }),
  write: async () => 0,
  copyFile: async () => {},
  stat: async () => ({ size: 0 }),
  unlinkSync: () => {},
};
export default fs;
