import { defineConfig, type Plugin } from 'vitest/config';
import { transformWithEsbuild } from 'vite';
import path from 'path';

// vitest(rolldown) 不识别 .ets 扩展名，会按 JS 解析导致 TS 语法报错；
// 在 transform 前用 esbuild 显式按 TypeScript 转译（本项目 .ets 为纯 TS 语法）
const etsAsTs: Plugin = {
  name: 'ets-as-ts',
  enforce: 'pre',
  async transform(code, id) {
    if (id.endsWith('.ets')) {
      return transformWithEsbuild(code, id.replace(/\.ets$/, '.ts'));
    }
  },
};

// 仅测试纯逻辑层（service/utils），HarmonyOS 运行时 API 以 __mocks__ 桩替换
export default defineConfig({
  plugins: [etsAsTs],
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    globals: false,
  },
  resolve: {
    // .ets 文件需纳入模块解析扩展名（源码内相对导入均省略扩展名）
    extensions: ['.mjs', '.js', '.mts', '.ts', '.jsx', '.tsx', '.json', '.ets'],
    alias: [
      // 源码导入形如 '@ohos.hilog'、'@ohos.data.relationalStore'（点号子模块，
      // 通配符别名对点号包名不可靠），逐个精确映射到测试桩文件
      { find: '@ohos.hilog', replacement: path.resolve(__dirname, 'tests/__mocks__/ohos/hilog.ts') },
      { find: '@ohos.data.relationalStore', replacement: path.resolve(__dirname, 'tests/__mocks__/ohos/data/relationalStore.ts') },
      { find: '@ohos.data.preferences', replacement: path.resolve(__dirname, 'tests/__mocks__/ohos/data/preferences.ts') },
      { find: '@ohos.util', replacement: path.resolve(__dirname, 'tests/__mocks__/ohos/util.ts') },
      { find: '@ohos.file.fs', replacement: path.resolve(__dirname, 'tests/__mocks__/ohos/file/fs.ts') },
      { find: '@ohos.file.picker', replacement: path.resolve(__dirname, 'tests/__mocks__/ohos/file/picker.ts') },
      { find: '@ohos.app.ability.common', replacement: path.resolve(__dirname, 'tests/__mocks__/ohos/app/ability/common.ts') },
      { find: '@ohos.zlib', replacement: path.resolve(__dirname, 'tests/__mocks__/ohos/zlib.ts') },
    ],
  },
  esbuild: {
    // 把 .ets 当 TypeScript 转译（本项目 .ets 为纯 TS 语法，无 ArkUI 装饰器之外的依赖）
    include: /\.(ts|js|tsx|ets)$/,
  },
  // vitest(rolldown) 将 .ets 视为 TypeScript 源码转译
  moduleTypes: {
    '.ets': 'ts',
  },
});
