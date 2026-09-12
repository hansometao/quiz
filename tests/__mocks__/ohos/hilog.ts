// @ohos.hilog 测试桩：与 HarmonyOS API 同签名，静默输出
const silent = () => {};
const hilog = {
  debug: silent,
  info: silent,
  warn: silent,
  error: silent,
  fatal: silent,
};
export default hilog;
