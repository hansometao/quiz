# quiz-harmony 鸿蒙题库练习 App

基于 ArkTS + ArkUI 的 HarmonyOS NEXT 应用，用于 Excel 题库的导入、练习与错题管理。
**完全离线本地运行**——无任何网络请求与第三方依赖，数据不出本机。

## 功能概览

- **Excel 题库导入**：解析 .xlsx（自研 OOXML 解析：zlib 解压 + 流式 XML 状态机），
  表头关键词自动映射（单选/多选/判断/填空/简答 5 种题型），异常行跳过并逐条报错；
  恶意文件防护（10 万行 / 256 列上限、50MB 大小上限）
- **六种练习模式**：顺序练习 / 随机练习 / 模拟考试（计时交卷）/ 错题专练 / 分类练习 / 难度练习
- **智能判题**：单选全等、多选排序无关（B,A,D ≡ ABD）、判断归一、填空关键词全包含
  （分号分隔、大小写不敏感）、简答不自动判分（待用户自评，不入错题本）
- **错题本**：连续答对 N 次自动移出（阈值 1-10 可配，默认 1），upsert 状态机 + 事务化移出
- **数据分析**：Canvas 自绘正确率趋势折线图 + 分类掌握度柱状图，按日增量统计（upsert 缓存表）
- **备份还原**：全量 JSON 导出/导入（50MB 上限 + 版本校验），还原前自动快照可回滚，
  错题 CSV 导出（公式注入防护）
- **响应式布局**：手机/平板/折叠屏三档断点（sm/md/lg），大列表 LazyForEach 虚拟化

## 环境要求

- DevEco Studio（HarmonyOS 官方 IDE）+ HarmonyOS NEXT SDK（API 12+）
- 真机或模拟器（HarmonyOS NEXT 5.0+）
- Node.js 22+ / Bun（仅运行测试需要，与 App 构建无关）

## 构建

```bash
hvigorw assembleHap          # 构建 HAP
```

应用数据存储于应用沙盒（`quiz.db` + preferences），无对外权限暴露。

## 测试

纯逻辑层（判题引擎/Excel 解析/CSV 转义）使用 Vitest 在 Node 下测试，
HarmonyOS 系统 Kit（@ohos.*）通过测试桩替换：

```bash
npm test                     # 或 bunx vitest run
```

- **16 个用例**：QuizEngine 判题（4 题型 + 边界/防御）、ExcelParser 枚举契约、
  BackupService csvEscape（公式注入防护/转义）、页面源码契约测试
  （页面成员定义/持久化接线的回归防护——ArkUI 页面无法在 Node 实例化，
  用源码级断言守护编译级错误）
- 测试配置：`vitest.config.ts`（ets-as-ts 转译插件 + @ohos.* 精确别名），
  系统桩位于 `tests/__mocks__/ohos/`

## 项目结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets        入口（DB 初始化/字体档位恢复/断点监听）
├── pages/                               12 个页面（主页/题库/导入/设置/答题/结果/统计等）
├── components/                          6 个组件（QuestionCard/EmptyState/LoadingOverlay 等）
├── service/
│   ├── DatabaseService.ets              DB 外观单例（PRAGMA foreign_keys / initPromise 防重入）
│   ├── QuizEngine.ets                   判题引擎（4 题型规则 + 洗牌 + 练习队列）
│   ├── ExcelParser.ets                  自研 xlsx 解析（表头映射/行数上限/UTF-8 流式解码）
│   └── repository/                      6 个 Repository（共享同一 RdbStore，参数化 SQL）
├── model/Models.ets                     数据模型与枚举（6 张表结构定义）
└── utils/                               LazyDataSource/BreakpointUtils 等
tests/                                   Vitest 测试（含 @ohos.* 桩与页面契约测试）
PROJECT_DOCUMENTATION.md                 完整项目文档（828 行：架构/数据库/依赖图/业务流程）
```

## 架构说明

经典分层：页面层 → 组件层 → 服务层（Repository 模式）→ 系统 Kit。
`DatabaseService` 为薄外观单例，6 个 Repository 共享同一 RdbStore；外键级联删除
（`PRAGMA foreign_keys = ON`，单连接长连场景）；统计走 upsert 缓存表避免全表扫描。
跨页实时刷新用 tabTick + @Watch；全局设置经 AppStorage + @StorageProp 广播。

## 安全与隐私

- 纯离线：无网络权限、无 WebView、无三方依赖（零供应链面）
- SQL 全参数化（RdbPredicates / ValuesBucket / `?` 绑定）
- 导入防御：xlsx 行列/大小上限、备份版本与类型强校验、CSV 公式注入转义
- 敏感数据仅存本地沙盒，备份文件请妥善保管
