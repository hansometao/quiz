// @ohos.data.relationalStore 测试桩：仅覆盖被导入的成员，不实现行为
const relationalStore = {
  SecurityLevel: { S1: 1 },
  StoreConfig: {},
  getRdbStore: async () => ({}),
};
export default relationalStore;
