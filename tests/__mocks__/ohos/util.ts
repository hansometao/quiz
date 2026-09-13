// @ohos.util 测试桩：TextDecoder.decodeWithStream 经 utilState 注入返回解码文本
//（BackupService 的 JSON 解析依赖该返回值）。
const utilState = {
  decodedText: '',
};

const util = {
  TextDecoder: {
    create: (_encoding?: string) => ({
      decodeWithStream: (_input: Uint8Array, _opts?: { stream?: boolean }) => utilState.decodedText,
    }),
  },
};
export default util;
export { utilState };
