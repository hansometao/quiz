// @ohos.util 测试桩：仅覆盖 BackupService 用到的 TextDecoder
const util = {
  TextDecoder: {
    create: (_encoding?: string) => ({
      decodeWithStream: (_input: Uint8Array, _opts?: { stream?: boolean }) => '',
    }),
  },
};
export default util;
