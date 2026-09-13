// @ohos.util 测试桩：TextDecoder.decodeWithStream 支持两种模式。
//   1) utilState.decodedText 显式注入（BackupService 校验链测试用）
//   2) 为 null 时真实 UTF-8 解码传入字节（ExcelParser readTextFile 全链用，
//      字节由 fs 桩的 readSync 按路径填入 buf）
const utilState = {
  decodedText: null as string | null,
};

const util = {
  TextDecoder: {
    create: (_encoding?: string) => ({
      decodeWithStream: (input: Uint8Array, _opts?: { stream?: boolean }) => {
        if (utilState.decodedText !== null) return utilState.decodedText;
        return new TextDecoder('utf-8').decode(input);
      },
    }),
  },
};
export default util;
export { utilState };
