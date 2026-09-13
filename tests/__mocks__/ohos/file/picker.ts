// @ohos.file.picker 测试桩：DocumentViewPicker.select 经 pickerState 注入返回 uri 列表。
const pickerState = {
  uris: [] as string[],
};

class DocumentViewPicker {
  constructor(_ctx?: unknown) {}
  async select(_opts?: unknown): Promise<string[]> {
    return pickerState.uris;
  }
}

const picker = { DocumentViewPicker };
export default picker;
export { pickerState };
