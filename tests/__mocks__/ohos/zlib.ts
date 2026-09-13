// @ohos.zlib 测试桩：覆盖 ZipUtils 实际导入的成员。
// 注意：ZipUtils 调用的是 decompressFile（非 unzipFile），
// 并引用 zlib.Options（类型标注，转译后擦除）与 CompressLevel 常量。
const zlib = {
  Options: {},
  CompressLevel: { COMPRESS_LEVEL_DEFAULT_COMPRESSION: 5 },
  decompressFile: async () => {},
};
export default zlib;
