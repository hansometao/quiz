// @ohos.data.preferences 测试桩
const preferences = {
  getPreferences: async () => ({ get: async (_k: string, d: unknown) => d, put: async () => {}, flush: async () => {} }),
};
export default preferences;
