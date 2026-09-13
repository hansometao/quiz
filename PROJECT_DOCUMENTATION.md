# quiz-harmony 项目文档

> 鸿蒙题库练习 App —— 完全离线本地运行的 HarmonyOS NEXT 题库练习应用

---

## 目录

- [1. 项目概述](#1-项目概述)
- [2. 技术栈与运行环境](#2-技术栈与运行环境)
- [3. 项目整体架构](#3-项目整体架构)
- [4. 目录结构](#4-目录结构)
- [5. 主要模块职责](#5-主要模块职责)
- [6. 关键类与函数说明](#6-关键类与函数说明)
- [7. 数据模型与数据库设计](#7-数据模型与数据库设计)
- [8. 模块间依赖关系](#8-模块间依赖关系)
- [9. 页面导航与业务流程](#9-页面导航与业务流程)
- [10. 项目运行方式](#10-项目运行方式)
- [11. 关键设计说明](#11-关键设计说明)

---

## 1. 项目概述

**quiz-harmony** 是一款基于 HarmonyOS NEXT 的题库练习应用，定位为「完全离线本地运行」的学习工具。用户可通过导入 Excel（.xlsx）题库文件，在 App 内进行顺序练习、随机练习、模拟考试、错题专练、分类练习、难度练习等多种练习模式，并支持错题本、历史记录、数据分析、备份还原等完整功能。

### 核心特性

| 特性 | 说明 |
| --- | --- |
| 完全离线 | 数据全部存储在本地 SQLite，不依赖任何网络服务 |
| Excel 导入 | 支持解析 .xlsx 文件，自动识别表头字段映射 |
| 多种练习模式 | 顺序 / 随机 / 模拟考试 / 错题专练 / 分类 / 难度 |
| 错题本 | 答错自动收录，连续答对可自动移出（阈值可配置） |
| 数据分析 | 折线图（正确率趋势）+ 柱状图（分类掌握度）|
| 备份还原 | 全量数据 JSON 备份 + 错题 CSV 导出 + 系统分享 |
| 响应式布局 | 支持手机 / 平板 / 折叠屏（sm/md/lg 三档断点）|
| 多题型支持 | 单选、多选、判断、填空、简答 |

---

## 2. 技术栈与运行环境

| 项 | 内容 |
| --- | --- |
| 开发语言 | ArkTS（HarmonyOS TypeScript 方言）|
| UI 框架 | ArkUI 声明式范式（@Component / @Entry / build()）|
| 应用类型 | HarmonyOS NEXT（API 12+），单 HAP 模块 |
| 兼容 SDK | 5.0.0(12) |
| 目标 SDK | 5.0.0(12) |
| 运行 OS | HarmonyOS |
| 构建工具 | hvigor（@ohos/hvigor-ohos-plugin）|
| 本地数据库 | relationalStore（SQLite）|
| 持久化偏好 | @ohos.data.preferences |
| 目标设备 | phone / tablet / 2in1 |
| 依赖三方库 | 无（纯系统 Kit，零外部依赖）|

### 申请的权限

**无**——module.json5 未声明任何 `requestPermissions`。应用完全离线运行：Excel 导入与备份文件选择均通过系统 Picker（DocumentViewPicker）由用户手动授权单次访问，无需媒体/文档读写权限；数据全部存储于应用沙盒。这是本项目的安全设计优点（零权限 = 零敏感授权面）。

---

## 3. 项目整体架构

项目采用经典的 **分层架构**，数据访问层进一步细化为 **Repository 模式**。自下而上分为：系统 Kit → 数据访问层（Repository）→ 服务层 → 工具层 → UI 组件层 → 页面层。

```
┌─────────────────────────────────────────────────────────────┐
│                      页面层 (pages/)                         │
│   Index / BankListPage / ImportPage / BankDetailPage /       │
│   PracticeConfigPage / QuizPage / ResultPage / MistakePage / │
│   HistoryPage / HistoryDetailPage / AnalysisPage / Settings  │
└───────────────────────────┬─────────────────────────────────┘
                            │ 调用
┌───────────────────────────▼─────────────────────────────────┐
│                  UI 组件层 (components/)                     │
│        BankCard / QuestionCard+OptionItem /                  │
│        EmptyState / LoadingOverlay / ProgressRing            │
└───────────────────────────┬─────────────────────────────────┘
                            │ 依赖
┌───────────────────────────▼─────────────────────────────────┐
│                    服务层 (service/)                         │
│  DatabaseService（单例/薄外观）  QuizEngine  ExcelParser      │
│  BackupService（单例）                                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │         数据访问层 (service/repository/)             │    │
│  │  BankRepo / QuestionRepo / SessionRepo /             │    │
│  │  StatsRepo / MistakeRepo / BackupRepo                │    │
│  └─────────────────────────────────────────────────────┘    │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│        工具层 (utils/)         │  ┌──────────────────────────┐
│ BreakpointUtils / DateUtils    │  │   数据模型 (model/)       │
│ LazyDataSource / XmlParser     │  │   Models.ets             │
│ ZipUtils                       │  │ （枚举/接口/类型定义）     │
└────────────────────────────────┘  └──────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                  HarmonyOS 系统 Kit                          │
│ relationalStore / preferences / file.fs / file.picker /     │
│ router / window / mediaquery / hilog / zlib / canvas /      │
│ util.TextDecoder                                            │
└─────────────────────────────────────────────────────────────┘
```

### 入口与生命周期

- 应用入口由 [module.json5](file:///workspace/entry/src/main/module.json5) 声明：`mainElement = "EntryAbility"`，`srcEntrance = "./ets/app.ets"`
- [app.ets](file:///workspace/entry/src/main/ets/app.ets) 提供全局生命周期回调（当前为空实现，预留扩展）
- [EntryAbility.ets](file:///workspace/entry/src/main/ets/entryability/EntryAbility.ets) 是 UIAbility，负责：
  - `onCreate`：初始化 `DatabaseService` 单例（异步 init）
  - `onWindowStageCreate`：注册 `BreakpointSystem` 响应式监听，加载首页 `pages/Index`
  - `onDestroy`：关闭数据库、注销断点监听

### 数据访问约定

所有持久化操作通过 `DatabaseService` 单例的 6 个公开仓库字段访问，调用约定：

```ts
const db = DatabaseService.getInstance();
await db.init(context);           // 仅 Ability 冷启动时调用一次
const banks    = await db.banks.getAll();
const questions = await db.questions.getByBank(bankId);
const session  = await db.sessions.insert(...);
const stats    = await db.stats.getOverall();
const mistakes = await db.mistakes.upsert(...);
await db.backup.restore(...);
```

---

## 4. 目录结构

```
quiz-harmony/
├── build-profile.json5          # 应用级构建配置（产物/SDK 版本）
├── hvigorfile.ts                # 应用级 hvigor 构建脚本
├── oh-package.json5             # OH 包描述（dependencies 为空）
├── package.json                 # npm 包描述（含 ohos.studioManifest）
├── PROJECT_DOCUMENTATION.md     # 本文档
├── hvigor/
│   └── hvigor-config.json5      # hvigor 配置
└── entry/                       # 唯一 HAP 模块
    ├── hvigorfile.ts            # 模块级 hvigor 构建脚本
    └── src/main/
        ├── module.json5         # 模块清单（权限/Ability/页面注册）
        ├── ets/
        │   ├── app.ets          # 全局入口
        │   ├── entryability/
        │   │   └── EntryAbility.ets
        │   ├── model/
        │   │   └── Models.ets                # 全部数据模型（枚举+接口）
        │   ├── service/
        │   │   ├── DatabaseService.ets       # 数据库服务（单例/薄外观）
        │   │   ├── QuizEngine.ets             # 出题与判题引擎
        │   │   ├── ExcelParser.ets            # xlsx 解析器
        │   │   ├── BackupService.ets          # 备份/还原服务（单例）
        │   │   └── repository/
        │   │       ├── BankRepository.ets     # 题库表
        │   │       ├── QuestionRepository.ets # 题目表
        │   │       ├── SessionRepository.ets  # 会话表 + 答题记录表
        │   │       ├── StatsRepository.ets    # 统计缓存 + 数据分析查询
        │   │       ├── MistakeRepository.ets  # 错题本表
        │   │       └── BackupRepository.ets   # 备份还原（批量写入/清除）
        │   ├── utils/
        │   │   ├── BreakpointUtils.ets        # 响应式断点（Breakpoint + BreakpointSystem）
        │   │   ├── DateUtils.ets              # 日期工具
        │   │   ├── LazyDataSource.ets         # 懒加载数据源 ArrayDataSource<T>
        │   │   ├── XmlParser.ets              # 极简 XML 解析器
        │   │   └── ZipUtils.ets               # 解压/文件读写/UTF-8 解码
        │   ├── components/
        │   │   ├── BankCard.ets               # 题库卡片
        │   │   ├── QuestionCard.ets           # 题目卡片 + OptionItem
        │   │   └── CommonComponents.ets       # EmptyState/LoadingOverlay/ProgressRing
        │   └── pages/
        │       ├── Index.ets                  # 主页（Tab 容器，@Entry）
        │       ├── BankListPage.ets           # 题库列表
        │       ├── ImportPage.ets             # Excel 导入（@Entry）
        │       ├── BankDetailPage.ets         # 题库详情（@Entry）
        │       ├── PracticeConfigPage.ets     # 练习配置（@Entry）
        │       ├── QuizPage.ets               # 答题页（@Entry）
        │       ├── ResultPage.ets             # 结果页（@Entry）
        │       ├── MistakePage.ets            # 错题本
        │       ├── HistoryPage.ets            # 历史记录
        │       ├── HistoryDetailPage.ets      # 历史详情（@Entry）
        │       ├── AnalysisPage.ets           # 数据分析
        │       └── SettingsPage.ets           # 设置
        └── resources/base/
            ├── element/
            │   ├── color.json                 # 颜色资源
            │   └── string.json                # 字符串资源
            └── profile/
                └── main_pages.json            # 页面路由注册表
```

### 页面注册表（main_pages.json）

下列 12 个页面被注册为路由（[main_pages.json](file:///workspace/entry/src/main/resources/base/profile/main_pages.json)），可被 `router.pushUrl` / `router.replaceUrl` 访问。其中 `pages/Index` 为应用启动首屏。

---

## 5. 主要模块职责

### 5.1 entryability — 应用入口

| 文件 | 职责 |
| --- | --- |
| [EntryAbility.ets](file:///workspace/entry/src/main/ets/entryability/EntryAbility.ets) | UIAbility 生命周期管理；冷启动初始化数据库；注册响应式断点；加载首页；销毁时释放资源 |

### 5.2 model — 数据模型层

| 文件 | 职责 |
| --- | --- |
| [Models.ets](file:///workspace/entry/src/main/ets/model/Models.ets) | 集中定义所有枚举（QuestionType / Difficulty / PracticeMode / SessionStatus / AnswerStatus）与接口（QuestionBank / Question / PracticeConfig / PracticeSession / AnswerRecord / QuestionStat / QuizResult / MistakeItem） |

### 5.3 service — 服务层

#### 服务外观与引擎

| 文件 | 模式 | 职责 |
| --- | --- | --- |
| [DatabaseService.ets](file:///workspace/entry/src/main/ets/service/DatabaseService.ets) | 单例 | 数据访问薄外观。初始化 RDB Store、建表、加载/同步错题阈值；持有并暴露 6 个 Repository；关闭数据库 |
| [QuizEngine.ets](file:///workspace/entry/src/main/ets/service/QuizEngine.ets) | 普通类 | 出题引擎：根据配置组装题目列表（取题/打乱/截断）；判题逻辑（各题型判定）；标签文案 |
| [ExcelParser.ets](file:///workspace/entry/src/main/ets/service/ExcelParser.ets) | 普通类 | 解析 .xlsx 文件为题目数组：解压 → 读 sharedStrings/sheet XML → 表头映射 → 行解析 |
| [BackupService.ets](file:///workspace/entry/src/main/ets/service/BackupService.ets) | 单例 | 全量 JSON 备份导出 / 文件选择器导入还原 / 错题 CSV 导出 / 系统分享 |

#### repository — 数据访问层（每个 Repository 持有同一个 RdbStore）

| 文件 | 对应表 | 职责 |
| --- | --- | --- |
| [BankRepository.ets](file:///workspace/entry/src/main/ets/service/repository/BankRepository.ets) | question_banks | 题库 CRUD + 统计查询（LEFT JOIN practice_sessions）+ 数量同步 |
| [QuestionRepository.ets](file:///workspace/entry/src/main/ets/service/repository/QuestionRepository.ets) | questions | 题目批量插入、分页筛选查询、错题专练取题、分类查询、收藏/标记/笔记元信息更新 |
| [SessionRepository.ets](file:///workspace/entry/src/main/ets/service/repository/SessionRepository.ets) | practice_sessions + answer_records | 会话创建/完成/放弃；答题记录插入（并 upsert question_stats）；按会话查询答题（JOIN 题目） |
| [StatsRepository.ets](file:///workspace/entry/src/main/ets/service/repository/StatsRepository.ets) | question_stats + 聚合查询 | 每日统计、分类统计、综合统计 |
| [MistakeRepository.ets](file:///workspace/entry/src/main/ets/service/repository/MistakeRepository.ets) | mistakes | 错题 upsert（答错）、连续正确计数与自动移出（答对）、查询错题本（JOIN 题目） |
| [BackupRepository.ets](file:///workspace/entry/src/main/ets/service/repository/BackupRepository.ets) | 全表 | 事务覆盖式还原（先清空六表再插入，主键引用预检过滤悬空行，返回插入/跳过计数）；清除全部历史记录 |

### 5.4 utils — 工具层

| 文件 | 职责 |
| --- | --- |
| [BreakpointUtils.ets](file:///workspace/entry/src/main/ets/utils/BreakpointUtils.ets) | 响应式断点系统：`Breakpoint` 常量（sm/md/lg）+ `BreakpointSystem` 通过 mediaquery 监听窗口尺寸，写入 `AppStorage['breakpoint']`；注册时先注销旧监听器避免泄漏 |
| [DateUtils.ets](file:///workspace/entry/src/main/ets/utils/DateUtils.ets) | 时间戳格式化（日期/日期时间/时长/可读时长/毫秒）|
| [LazyDataSource.ets](file:///workspace/entry/src/main/ets/utils/LazyDataSource.ets) | 通用 `ArrayDataSource<T>`，实现 IDataSource，配合 LazyForEach 实现大列表虚拟化 |
| [XmlParser.ets](file:///workspace/entry/src/main/ets/utils/XmlParser.ets) | 极简 XML 解析器（纯字符串状态机），提供 parseXml / findFirst / findAll / findAllDeep |
| [ZipUtils.ets](file:///workspace/entry/src/main/ets/utils/ZipUtils.ets) | 基于 @ohos.zlib 的 unzip、readTextFile、pathExists、rmdir、decodeUtf8 工具函数 |

### 5.5 components — UI 组件层

| 文件 | 组件 | 职责 |
| --- | --- | --- |
| [BankCard.ets](file:///workspace/entry/src/main/ets/components/BankCard.ets) | `BankCard` | 题库卡片：标题/描述/统计/上次练习时间/查看详情/开始练习 |
| [QuestionCard.ets](file:///workspace/entry/src/main/ets/components/QuestionCard.ets) | `OptionItem` | 单个选项渲染，支持选中/已提交/正确性高亮 |
| 同上 | `QuestionCard` | 题目卡片：题型/难度/分类标签 + 题干 + 各题型作答区 + 解析展示 |
| [CommonComponents.ets](file:///workspace/entry/src/main/ets/components/CommonComponents.ets) | `EmptyState` | 空状态占位（图标+标题+副标题+操作按钮）|
| 同上 | `LoadingOverlay` | 全屏加载遮罩 |
| 同上 | `ProgressRing` | Canvas 自绘进度环（用于结果页正确率展示）|

### 5.6 pages — 页面层

| 文件 | @Entry | 职责 |
| --- | :---: | --- |
| [Index.ets](file:///workspace/entry/src/main/ets/pages/Index.ets) | ✅ | 主页，5 个 Tab 容器（题库/错题本/历史/分析/设置）|
| [BankListPage.ets](file:///workspace/entry/src/main/ets/pages/BankListPage.ets) | | 题库列表，进入练习/详情/导入 |
| [ImportPage.ets](file:///workspace/entry/src/main/ets/pages/ImportPage.ets) | ✅ | 选 Excel → 解析 → 预览结果 → 保存题库 |
| [BankDetailPage.ets](file:///workspace/entry/src/main/ets/pages/BankDetailPage.ets) | ✅ | 题库详情：分页 LazyForEach + 筛选 Chip + 长按上下文菜单（删除/收藏/笔记）|
| [PracticeConfigPage.ets](file:///workspace/entry/src/main/ets/pages/PracticeConfigPage.ets) | ✅ | 练习配置：模式/题数/分类/限时/选项 |
| [QuizPage.ets](file:///workspace/entry/src/main/ets/pages/QuizPage.ets) | ✅ | 答题页：进度/计时/作答/提交/跳过/上下题/完成 |
| [ResultPage.ets](file:///workspace/entry/src/main/ets/pages/ResultPage.ets) | ✅ | 结果页：进度环 + 正确/错误/跳过 + 本次错题列表 |
| [MistakePage.ets](file:///workspace/entry/src/main/ets/pages/MistakePage.ets) | | 错题本：列表 + 连续正确进度 + 专项练习入口 |
| [HistoryPage.ets](file:///workspace/entry/src/main/ets/pages/HistoryPage.ets) | | 历史练习列表，点击进入详情 |
| [HistoryDetailPage.ets](file:///workspace/entry/src/main/ets/pages/HistoryDetailPage.ets) | ✅ | 单次练习全部答题记录，可展开查看解析 |
| [AnalysisPage.ets](file:///workspace/entry/src/main/ets/pages/AnalysisPage.ets) | | 数据分析：综合统计 + 折线图 + 柱状图（Canvas 自绘）|
| [SettingsPage.ets](file:///workspace/entry/src/main/ets/pages/SettingsPage.ets) | | 设置：外观/反馈/学习/备份/数据管理/关于 |

---

## 6. 关键类与函数说明

### 6.1 DatabaseService（单例 / 薄外观）

文件：[DatabaseService.ets](file:///workspace/entry/src/main/ets/service/DatabaseService.ets)。

它本身不做业务 CRUD，而是初始化 RDB Store、建表、管理偏好阈值，并把 6 个 Repository 作为公开字段暴露。各 Repository 持有同一个 `RdbStore` 实例。

#### 静态/属性

| 成员 | 说明 |
| --- | --- |
| `static getInstance()` | 获取单例 |
| `banks: BankRepository` | 题库仓库 |
| `questions: QuestionRepository` | 题目仓库 |
| `sessions: SessionRepository` | 会话 + 答题记录仓库 |
| `stats: StatsRepository` | 统计 + 分析仓库 |
| `mistakes: MistakeRepository` | 错题本仓库 |
| `backup: BackupRepository` | 备份/还原/清除仓库 |
| `autoRemoveThreshold: number` | 错题自动移出阈值（默认 3，getter）|

#### 生命周期与配置

| 方法 | 说明 |
| --- | --- |
| `init(context)` | 初始化 RDB Store + 建表 + 加载阈值 + 实例化 6 个 Repository（EntryAbility.onCreate 调用）|
| `loadThreshold(context)` | 从 preferences 读取阈值（私有）|
| `syncAutoRemoveThreshold(n)` | 同步阈值到内存与 preferences（设置页调用）|
| `close()` | 关闭数据库（EntryAbility.onDestroy 调用）|

### 6.2 BankRepository（题库表）

文件：[BankRepository.ets](file:///workspace/entry/src/main/ets/service/repository/BankRepository.ets)。

| 方法 | 说明 |
| --- | --- |
| `insert(name, description, fileName)` | 插入题库，返回新 ID |
| `getAll()` | 查询全部题库（LEFT JOIN practice_sessions 携带练习次数/平均正确率/上次练习时间）|
| `getById(id)` | 根据 ID 查题库 |
| `update(id, name, description)` | 更新题库信息 |
| `delete(id)` | 删除题库（外键级联删除题目/会话）|
| `refreshCount(bankId)` | 同步题库题目数量（子查询 COUNT）|

### 6.3 QuestionRepository（题目表）

文件：[QuestionRepository.ets](file:///workspace/entry/src/main/ets/service/repository/QuestionRepository.ets)。

| 方法 | 说明 |
| --- | --- |
| `batchInsert(bankId, questions[])` | 事务批量插入题目 |
| `getByBank(bankId, options?)` | 分页查询，支持 types/categories/difficulties 筛选 + LEFT JOIN question_stats 统计 |
| `getMistakesForPractice(bankId?)` | 错题专练取题（基于 mistakes 表 JOIN，bankId 为 0/undefined 表示全库）|
| `getCategories(bankId)` | 获取题库下所有非空分类 |
| `deleteById(id)` | 删除单题 |
| `updateMeta(id, {isStarred?, isFlagged?, userNote?})` | 更新收藏/标记/笔记 |
| `getByIds(ids[])` | 批量按 ID 查题目 |
| `getById(id)` | 按 ID 查单题 |
| `rowToQuestion(result)` | ResultSet → Question（供本类与 SessionRepo/MistakeRepo 复用）|

`QuestionQueryOptions`：`{ types?, categories?, difficulties?, limit?, offset? }`

### 6.4 SessionRepository（会话表 + 答题记录表）

文件：[SessionRepository.ets](file:///workspace/entry/src/main/ets/service/repository/SessionRepository.ets)。

| 方法 | 说明 |
| --- | --- |
| `insert(bankId, mode, config, totalCount)` | 创建会话（status=ongoing，config 序列化为 JSON），返回 sessionId |
| `finish(id, correctCount, durationSec, totalScore)` | 完成会话（status=completed）|
| `abandon(id)` | 放弃会话（status=abandoned）|
| `getCompleted(limit, bankId?)` | 查询已完成会话（JOIN bank 取名）|
| `getById(id)` | 按 ID 查会话（不限制状态，JOIN bank 取名）|
| `getAll()` | 查询全部会话（含未完成，供备份）|
| `insertAnswer(sessionId, questionId, userAnswer, isCorrect, timeSpentMs)` | 插入答题记录并同步 upsert question_stats |
| `getAnswersBySession(sessionId)` | 查询某会话全部答题（JOIN questions 携带题目信息）|
| `getAllAnswers()` | 仅查 answer_records（供备份）|

### 6.5 StatsRepository（统计缓存 + 数据分析）

文件：[StatsRepository.ets](file:///workspace/entry/src/main/ets/service/repository/StatsRepository.ets)。

| 方法 | 说明 |
| --- | --- |
| `getDailyStats(days=14)` | 近 N 天每日练习次数与正确率（GROUP BY 日期，localtime）|
| `getCategoryStats(bankId?)` | 各分类正确率（基于 question_stats 聚合）|
| `getOverall()` | 综合统计：总会话数/总题数/平均正确率/总用时 |

返回类型：`DailyStat { date, count, correctRate }`、`CategoryStat { category, attemptCount, correctCount, correctRate }`、`OverallStat { totalSessions, totalQuestions, avgCorrectRate, totalDurationSec }`。

### 6.6 MistakeRepository（错题本表）

文件：[MistakeRepository.ets](file:///workspace/entry/src/main/ets/service/repository/MistakeRepository.ets)。

| 方法 | 说明 |
| --- | --- |
| `upsert(questionId, bankId, myAnswer)` | 答错时 upsert，wrongCount+1，consecutiveCorrect 清零 |
| `onCorrectAnswer(questionId, threshold)` | 答对时 consecutiveCorrect+1，达到阈值自动 DELETE |
| `remove(questionId)` | 手动移出错题 |
| `getWithQuestions(bankId?)` | 查询错题本（JOIN questions + question_stats 携带题目）|
| `getAll()` | 查全部错题（供备份）|

### 6.7 BackupRepository（备份/还原/清除）

文件：[BackupRepository.ets](file:///workspace/entry/src/main/ets/service/repository/BackupRepository.ets)。

| 方法 | 说明 |
| --- | --- |
| `restore(banks, questions, sessions, records, mistakes)` | 事务覆盖式还原：先清空全部业务表再插入（保留原 ID），还原前按备份内主键集合做引用预检，悬空引用行跳过计入 skipped，返回 `{ inserted, skipped }` |
| `clearAllHistory()` | 清除答题/会话/统计/错题（保留题库与题目），事务执行 |

### 6.8 QuizEngine（出题与判题引擎）

文件：[QuizEngine.ets](file:///workspace/entry/src/main/ets/service/QuizEngine.ets)。

| 方法 | 说明 |
| --- | --- |
| `buildQuestionList(bankId, config)` | 根据配置出题：MISTAKE 模式取错题本；其他模式取题库（带筛选）；RANDOM/EXAM 模式 Fisher-Yates 打乱；按 totalCount 截断 |
| `checkAnswer(question, userAnswer)` | 判题：SINGLE/JUDGE 全等；MULTI 字母排序比较；FILL 关键词全部包含；ESSAY 不自动判（返回 false）|
| `static difficultyLabel(d)` | 难度 → 中文（简单/中等/困难）|
| `static typeLabel(t)` | 题型 → 中文（单选题/多选题/...）|
| `static modeLabel(m)` | 模式 → 中文（顺序练习/随机练习/...）|
| `private shuffle(arr)` | Fisher-Yates 洗牌 |

### 6.9 ExcelParser（Excel 解析器）

文件：[ExcelParser.ets](file:///workspace/entry/src/main/ets/service/ExcelParser.ets)。

| 成员 | 说明 |
| --- | --- |
| `parse(filePath, tmpDir)` | 主流程：unzip → readSharedStrings → readSheet(1) → parseSheetRows → buildFieldMap → 逐行 parseRow → readBankName（Sheet2 或文件名）→ 清理临时目录 |
| `FIELD_KEYWORDS` | 表头识别关键词映射（如 `'题目'`/`'question'`/`'题干'` → `question` 字段）|
| `parseType(s)` | 题型文字 → QuestionType |
| `parseDifficulty(s)` | 难度文字 → Difficulty |
| `normalizeAnswer(answer, type)` | 答案规范化：判断题转「正确/错误」；多选去分隔符转大写连续字母；其他转大写 |
| `parseSheetRows(sheetXml, sharedStrings)` | 解析 sheetData XML 为二维字符串数组，处理共享字符串索引 |
| `ParseResult` | 解析结果：questions / skipped / errors / bankName |

### 6.10 BackupService（备份服务单例）

文件：[BackupService.ets](file:///workspace/entry/src/main/ets/service/BackupService.ets)。

| 方法 | 说明 |
| --- | --- |
| `exportBackup(ctx)` | 分批并发（mapBatched，批上限 8）拉取各题库题目与各会话答题记录 → JSON → 写入沙盒 `filesDir/quiz_backup_YYYYMMDD_HHmm.quizbackup` → 返回路径 |
| `importBackup(ctx)` | 弹 DocumentViewPicker → 拷贝到 cacheDir → `util.TextDecoder.decodeWithStream` 解码 → 校验 → `backup.restore` → 清理临时文件，返回 `{ success, message }` |
| `exportMistakesCSV(ctx)` | 拉取全部错题 → 拼装 CSV（含分类/难度/解析等完整字段，带 UTF-8 BOM）→ 写入沙盒 |
| `shareFile(ctx, filePath)` | 通过 `ohos.want.action.sendData` 调起系统分享 |
| `private csvEscape(s)` | CSV 字段转义（含逗号/引号/换行时包裹双引号）|
| `private safeUnlink(path)` | 安全删除临时文件，失败不抛错 |

### 6.11 工具类

#### BreakpointUtils（[BreakpointUtils.ets](file:///workspace/entry/src/main/ets/utils/BreakpointUtils.ets)）

| 成员 | 说明 |
| --- | --- |
| `Breakpoint.SM/MD/LG` | 断点常量：sm < 600vp / 600~840vp / > 840vp |
| `BreakpointSystem.register(windowStage)` | 先注销旧监听器（防泄漏）→ 读初始窗口宽度定断点 → 注册 3 个 mediaquery 监听器，匹配时写入 `AppStorage['breakpoint']` |
| `BreakpointSystem.unregister()` | 注销 3 个监听器 |

#### DateUtils（[DateUtils.ets](file:///workspace/entry/src/main/ets/utils/DateUtils.ets)）

| 方法 | 说明 |
| --- | --- |
| `formatDate(unixSec)` | → "YYYY-MM-DD" |
| `formatDateTime(unixSec)` | → "YYYY-MM-DD HH:mm" |
| `formatDuration(sec)` | → "mm:ss" 或 "HH:mm:ss" |
| `formatDurationLabel(sec)` | → "X小时X分X秒" |
| `formatMs(ms)` | 毫秒 → "1.2s"/"2m30s" 等 |
| `today()` / `now()` | 今日字符串 / 当前 Unix 秒 |

#### ArrayDataSource（[LazyDataSource.ets](file:///workspace/entry/src/main/ets/utils/LazyDataSource.ets)）

| 方法 | 说明 |
| --- | --- |
| `totalCount()` / `getData(index)` | IDataSource 实现 |
| `registerDataChangeListener` / `unregisterDataChangeListener` | 注册/注销变更监听 |
| `setData(arr)` / `push(item)` / `update(i, item)` / `remove(i)` / `clear()` | 数据操作并触发对应 notify |
| `getAll()` | 获取底层数组（只读） |

#### XmlParser（[XmlParser.ets](file:///workspace/entry/src/main/ets/utils/XmlParser.ets)）

| 函数 | 说明 |
| --- | --- |
| `parseXml(xml)` | 状态机解析 XML，去命名空间前缀，处理 CDATA 与实体 |
| `findFirst(node, tag)` | 递归查找首个匹配节点 |
| `findAll(node, tag)` | 直接子节点中查找全部匹配 |
| `findAllDeep(node, tag)` | 递归查找全部匹配 |

#### ZipUtils（[ZipUtils.ets](file:///workspace/entry/src/main/ets/utils/ZipUtils.ets)）

| 函数 | 说明 |
| --- | --- |
| `unzip(zipPath, destDir)` | 基于 @ohos.zlib 解压到目标目录 |
| `readTextFile(path)` | 读取文件并 UTF-8 解码（支持 BOM）|
| `pathExists(path)` | 检查路径是否存在 |
| `rmdir(path)` | 递归删除目录（含文件）|
| `decodeUtf8(buf)` | 使用 `util.TextDecoder` 流式解码，避免多字节字符边界问题 |

---

## 7. 数据模型与数据库设计

### 7.1 数据模型（Models.ets）

#### 枚举

```ts
QuestionType  // SINGLE | MULTI | JUDGE | FILL | ESSAY
Difficulty    // EASY(1) | MEDIUM(2) | HARD(3)
PracticeMode  // SEQUENTIAL | RANDOM | EXAM | MISTAKE | CATEGORY | DIFFICULTY
SessionStatus // ONGOING | COMPLETED | ABANDONED
AnswerStatus  // WRONG(0) | CORRECT(1) | SKIPPED(2)
```

#### 核心接口

- **QuestionBank**：题库（id/name/description/fileName/totalCount/createdAt/updatedAt + 运行时统计 practiceCount/avgCorrectRate/lastPracticeAt）
- **Question**：题目（id/bankId/seqNo/type/question/optionA~E/answer/explanation/category/difficulty/score/isStarred/isFlagged/userNote/createdAt + 运行时统计 attemptCount/correctCount/lastAnswered）
- **PracticeConfig**：练习配置（mode/totalCount/types/categories/difficulties/timeLimitSec/showExplanation/allowSkip），序列化为 JSON 存入 `config_json` 字段
- **PracticeSession**：练习会话（id/bankId/mode/configJson/totalCount/correctCount/durationSec/totalScore/status/startedAt/finishedAt + 运行时 bankName/config）
- **AnswerRecord**：答题记录（id/sessionId/questionId/userAnswer/isCorrect/timeSpentMs/answeredAt + 运行时 question）
- **QuestionStat**：题目统计缓存（questionId/attemptCount/correctCount/lastAnswered/updatedAt）
- **MistakeItem**：错题记录（questionId/bankId/wrongCount/consecutiveCorrect/myLastAnswer/lastPracticeTime/addedAt + 运行时 question）
- **QuizResult**：答题结果汇总（用于结果页）

### 7.2 数据库表设计

数据库名 `quiz.db`，安全级别 S1。共 6 张表 + 6 个索引（建表 SQL 集中在 [DatabaseService.ets](file:///workspace/entry/src/main/ets/service/DatabaseService.ets) 的 `CREATE_SQL`）。

| 表名 | 主键 | 说明 | 关键外键 |
| --- | --- | --- | --- |
| `question_banks` | id | 题库 | — |
| `questions` | id | 题目 | bank_id → question_banks(id) ON DELETE CASCADE |
| `practice_sessions` | id | 练习会话 | bank_id → question_banks(id) ON DELETE CASCADE |
| `answer_records` | id | 答题记录 | session_id → practice_sessions(id) ON DELETE CASCADE；question_id → questions(id) ON DELETE CASCADE |
| `question_stats` | question_id | 题目统计缓存 | question_id → questions(id) ON DELETE CASCADE |
| `mistakes` | question_id | 错题本 | question_id → questions(id) ON DELETE CASCADE |

#### 索引

- `idx_questions_bank` (questions.bank_id)
- `idx_questions_category` (questions.bank_id, category)
- `idx_questions_type` (questions.bank_id, type)
- `idx_answer_session` (answer_records.session_id)
- `idx_answer_question` (answer_records.question_id)
- `idx_session_bank` (practice_sessions.bank_id)

#### 关键设计要点

1. **级联删除**：所有子表对 questions/question_banks/practice_sessions 均 `ON DELETE CASCADE`，删除题库时自动清理题目与会话，删除会话时自动清理答题记录。
2. **统计缓存表**：`question_stats` 通过 `INSERT ON CONFLICT DO UPDATE` 实现 upsert（在 `SessionRepository.insertAnswer` 中执行），避免每次分析全表扫描 answer_records。
3. **错题本独立表**：`mistakes` 与 `question_stats` 分离，支持「连续答对 N 次自动移出」的精细化逻辑，且独立维护 `wrong_count`、`consecutive_correct`、`my_last_answer`。
4. **配置 JSON 序列化**：`PracticeConfig` 以 JSON 字符串存入 `practice_sessions.config_json`，避免拆表。

---

## 8. 模块间依赖关系

### 8.1 服务层与 Repository 依赖

```
DatabaseService ──持有──► 6 个 Repository（共享同一 RdbStore）
                 ──depends on──► model/Models
                 ──depends on──► @ohos.data.relationalStore
                 ──depends on──► @ohos.data.preferences
                 ──depends on──► @ohos.app.ability.common
                 ──depends on──► @ohos.hilog

BankRepository     ──depends on──► model/Models, relationalStore
QuestionRepository ──depends on──► model/Models, relationalStore
SessionRepository  ──depends on──► model/Models, relationalStore, QuestionRepository（复用 rowToQuestion）
StatsRepository    ──depends on──► relationalStore
MistakeRepository  ──depends on──► model/Models, relationalStore, QuestionRepository（复用 rowToQuestion）
BackupRepository   ──depends on──► model/Models, relationalStore

QuizEngine ──depends on──► model/Models
            ──depends on──► DatabaseService（取题用）

ExcelParser ──depends on──► utils/ZipUtils (unzip/readTextFile/pathExists/rmdir)
             ──depends on──► utils/XmlParser (parseXml/findFirst/findAll/findAllDeep)
             ──depends on──► model/Models

BackupService ──depends on──► DatabaseService（拉取/还原数据）
               ──depends on──► model/Models
               ──depends on──► @ohos.file.fs / @ohos.file.picker / @ohos.util / @ohos.app.ability.common
```

### 8.2 页面层依赖

| 页面 | 依赖服务/工具 | 依赖组件 |
| --- | --- | --- |
| Index | — | 5 个子页面（BankList/Mistake/History/Analysis/Settings）|
| BankListPage | DatabaseService.banks | BankCard, EmptyState, LoadingOverlay |
| ImportPage | ExcelParser, DatabaseService.banks/questions | LoadingOverlay |
| BankDetailPage | DatabaseService.banks/questions, QuizEngine | EmptyState, LoadingOverlay, ArrayDataSource, DateUtils |
| PracticeConfigPage | DatabaseService.banks/questions, QuizEngine | — |
| QuizPage | DatabaseService.sessions/mistakes, QuizEngine | QuestionCard, LoadingOverlay, DateUtils |
| ResultPage | DatabaseService.sessions | ProgressRing, LoadingOverlay, DateUtils |
| MistakePage | DatabaseService.mistakes, QuizEngine | EmptyState, LoadingOverlay |
| HistoryPage | DatabaseService.sessions, QuizEngine, DateUtils | EmptyState, LoadingOverlay |
| HistoryDetailPage | DatabaseService.sessions, QuizEngine, DateUtils | EmptyState, LoadingOverlay |
| AnalysisPage | DatabaseService.stats, DateUtils | LoadingOverlay |
| SettingsPage | DatabaseService, BackupService, preferences | — |

### 8.3 入口 Ability 依赖

```
EntryAbility ──depends on──► DatabaseService (init / close)
              ──depends on──► BreakpointSystem (register / unregister)
              ──depends on──► @ohos.app.ability.UIAbility
              ──depends on──► @ohos.window
              ──depends on──► @ohos.hilog
```

---

## 9. 页面导航与业务流程

### 9.1 主导航结构

```
EntryAbility
    └── pages/Index（@Entry，Tab 容器，底部 5 Tab）
            ├── Tab 0: BankListPage ──┐
            ├── Tab 1: MistakePage    │
            ├── Tab 2: HistoryPage    │  路由跳转
            ├── Tab 3: AnalysisPage   │
            └── Tab 4: SettingsPage ──┘
```

### 9.2 题库导入与练习主流程

```
BankListPage
   │ +（右上）
   ▼
ImportPage ──选 xlsx──► ExcelParser.parse ──预览（成功/跳过/错误）──► 保存题库
   │                                              │
   │                                  banks.insert + questions.batchInsert + banks.refreshCount
   │                                              │
   └──────────────────────────────────────────────┘
   │
   │ 点击题库卡片
   ├──►「查看详情」──► BankDetailPage（LazyForEach 分页 + 筛选 + 长按菜单）
   │
   └──►「开始练习」──► PracticeConfigPage
                            │ 配置 mode/totalCount/categories/timeLimit/options
                            ▼
                        QuizPage
                            │ initQuiz: QuizEngine.buildQuestionList + sessions.insert
                            │ 逐题作答: checkAnswer + sessions.insertAnswer + mistakes.upsert/onCorrectAnswer
                            │ 完成: sessions.finish + 计算 score
                            ▼
                        ResultPage（router.replaceUrl，避免返回到答题页重新出题）
                            │ ProgressRing + 错题列表
                            │「再做一次」router.back /「返回首页」router.pushUrl Index
```

### 9.3 错题本流程

```
QuizPage（答错）─► MistakeRepository.upsert
                       │ wrong_count +1, consecutive_correct = 0
                       ▼
MistakePage ──mistakes.getWithQuestions──► 错题列表（含连续正确进度）
                       │
                       │ 「专项练习」（传 bankId=0 表示全库错题）
                       ▼
              PracticeConfig (mode=MISTAKE) ──► QuizPage
                       │
                  答对时 mistakes.onCorrectAnswer
                  consecutive_correct +1
                  达到阈值（默认3）→ 自动 DELETE mistakes
```

### 9.4 历史与分析流程

```
HistoryPage ──sessions.getCompleted──► 列表
                │ 点击
                ▼
        HistoryDetailPage ──sessions.getAnswersBySession──► 全部答题记录（可展开解析）

AnalysisPage ──stats.getOverall + getDailyStats + getCategoryStats──► Canvas 自绘折线图/柱状图
              （支持 7/14/30 天切换）
```

### 9.5 备份还原流程

```
SettingsPage
   ├──「导出备份」─► BackupService.exportBackup ──► shareFile（系统分享）
   ├──「导入还原」─► BackupService.importBackup ──► DocumentViewPicker ──► backup.restore（追加模式）
   ├──「导出错题」─► BackupService.exportMistakesCSV ──► shareFile
   └──「清除记录」─► DatabaseService.backup.clearAllHistory（保留题库与题目）
```

### 9.6 路由 API 使用约定

- `router.pushUrl`：常规入栈（保留返回）
- `router.replaceUrl`：替换栈顶（用于 QuizPage → ResultPage，避免返回到答题页重新出题）
- `router.back()`：返回上一页
- 参数传递：通过 `router.getParams() as Record<string, T>` 读取，`config` 以 JSON 字符串传递后 `JSON.parse`

---

## 10. 项目运行方式

### 10.1 环境准备

1. 安装 **DevEco Studio**（HarmonyOS 官方 IDE，建议最新版本，需支持 API 12+）。
2. 在 DevEco Studio 中配置 HarmonyOS SDK：
   - 兼容 SDK：`5.0.0(12)`
   - 目标 SDK：`5.0.0(12)`
3. （可选）配置签名：在 [build-profile.json5](file:///workspace/build-profile.json5) 的 `app.signingConfigs` 中配置签名信息，或使用 DevEco Studio 的「自动签名」。

### 10.2 打开与构建

1. 启动 DevEco Studio → `File > Open` → 选择项目根目录。
2. 等待 hvigor 同步完成（项目无任何外部依赖，同步很快）。
3. 构建方式：
   - **IDE**：点击 `Run` 按钮，或 `Build > Build Hap(s)/APP(s)`。
   - **命令行**（需配置 hvigor 命令行环境）：
     ```bash
     hvigorw assembleHap      # 构建 HAP
     hvigorw clean            # 清理
     ```

### 10.3 运行

1. 连接 HarmonyOS 真机或启动模拟器（需 HarmonyOS NEXT 系统）。
2. 在 DevEco Studio 顶部选择目标设备。
3. 点击 `Run`，IDE 会自动安装并启动应用。
4. 首次运行需授权存储/文档读写权限（用于 Excel 导入与备份导出）。

### 10.4 调试

- 日志通过 `hilog` 输出，TAG 包括：`EntryAbility`、`DatabaseService`、`ExcelParser`、`ZipUtils`、`BreakpointUtils`。
- 可在 DevEco Studio 的 HiLog 面板按 TAG 过滤查看。

### 10.5 Excel 题库文件规范

导入的 `.xlsx` 文件需满足：

- 第一行为表头，后续行为题目数据。
- **必填字段**：题目（`题目`/`题干`/`question`/`问题`/`stem`）、题型（`题型`/`type`/`类型`）、答案（`答案`/`answer`/`正确答案`/`标准答案`）。
- **选填字段**：选项 A~E（`选项A`/`option_a`/`a选项` 等）、解析、分类、难度、分值、序号。
- 表头识别基于关键词包含匹配（详见 `ExcelParser.FIELD_KEYWORDS`），大小写不敏感。
- 可选 Sheet2 第一行第二个单元格作为题库名，否则取文件名（去扩展名）。
- 题型支持中文/英文（如「单选」/`single`）；难度支持「简单/中等/困难」或 `easy`/数字 `1/2/3`。
- 答案为空的行会被跳过并在错误列表中提示。

### 10.6 备份文件格式

- 备份文件扩展名：`.quizbackup`，实际为 JSON。
- 顶层结构：
  ```json
  {
    "version": 1,
    "exportTime": "ISO-8601",
    "banks": [...],
    "questions": [...],
    "sessions": [...],
    "answerRecords": [...],
    "mistakes": [...]
  }
  ```
- 还原策略：覆盖模式——事务内先清空六张业务表再插入备份数据（保留原 ID 关系），还原前做引用预检，悬空引用行跳过（计入 skipped）。还原前自动快照存于沙盒 `filesDir/pre_restore_snapshot.quizbackup`，可在设置页「撤销还原」回滚。
- 错题 CSV 导出带 UTF-8 BOM（`\uFEFF`），保证 Excel 正确识别编码，包含分类/难度/解析/错误次数等完整字段。

---

## 11. 关键设计说明

### 11.1 Repository 模式

`DatabaseService` 仅作薄外观，自身只负责初始化（建表、加载偏好、实例化仓库）与配置同步（错题阈值）。所有业务 CRUD 按数据域拆分到 6 个 Repository，每个 Repository 持有同一个 `RdbStore` 实例，职责单一、可独立演进。`QuestionRepository.rowToQuestion` 被多个 Repository 复用以解析题目行。

### 11.2 单例模式

- `DatabaseService` 与 `BackupService` 使用经典私有构造 + 静态 `getInstance()` 单例，确保全局唯一数据库连接与备份服务实例。
- `BreakpointSystem` 使用静态方法 + 静态字段管理监听器生命周期，本质也是全局单例。

### 11.3 响应式布局

- 入口 Ability 注册 `BreakpointSystem`，通过 `mediaquery` 监听窗口宽度变化，将当前断点（`sm`/`md`/`lg`）写入 `AppStorage['breakpoint']`。
- 组件内通过 `@StorageProp('breakpoint')` 订阅断点变化。
- 注册时先调用 `unregister()` 注销旧监听器，避免 Ability 重建导致监听器累积泄漏。

### 11.4 列表虚拟化

- `BankDetailPage` 题目列表使用 `LazyForEach` + `ArrayDataSource`，分页加载（`PAGE_SIZE = 30`），滚动到底（`onScrollEdge` 检测 `Edge.Bottom`）自动加载下一页，避免大题库一次渲染全部节点。

### 11.5 判题策略

| 题型 | 判定规则 |
| --- | --- |
| 单选 / 判断 | 答案字符串去空格大写后全等比较 |
| 多选 | 字母去分隔符后排序比较（如 `B,A,D` ≡ `ABD`）|
| 填空 | 答案以分号分隔为关键词，用户答案需全部包含（小写比较）|
| 简答 | 不自动判，返回 false，标记为 `SKIPPED`（待核），不计入错题本 |

### 11.6 错题本自动移出机制

- 答错：`MistakeRepository.upsert` → `wrong_count +1`，`consecutive_correct = 0`。
- 答对：`MistakeRepository.onCorrectAnswer` → `consecutive_correct +1`；若 `consecutive_correct >= threshold` 则自动 `DELETE`。
- 阈值由用户在设置页配置（1~10，默认 3），实时同步至 `DatabaseService._autoRemoveThreshold`（内存 + preferences）。

### 11.7 简答题与跳过的处理

- 简答题 `submit` 时 `isCorrect = AnswerStatus.SKIPPED`，**不进入错题本**，也不触发连续正确计数。
- 用户主动「跳过」时记录 `userAnswer = ''`、`isCorrect = SKIPPED`、`timeSpentMs = 0`，并用 `skippedIndices` 数组标记，避免污染 answers Map。

### 11.8 兜底数据组装

- `ResultPage` 与 `HistoryDetailPage` 在 `getCompleted` 找不到对应 session 时，会先用 `sessions.getById`（不限制状态）兜底查询；若仍找不到但答题记录存在，则基于答题记录手动组装 `PracticeSession` 兜底对象（用时取首末答题时间差），避免页面空白。

### 11.9 零外部依赖

- 项目 `oh-package.json5` 与 `package.json` 的 `dependencies` 均为空。
- xlsx 解析完全自研（基于 `@ohos.zlib` 解压 + 自研 `XmlParser` 解析 OOXML），无需引入 SheetJS 等三方库。
- 图表（折线图/柱状图/进度环）全部使用 ArkUI `Canvas` 自绘，无图表库依赖。

### 11.10 配置持久化

- 用户偏好（字体大小/音效/振动/错题阈值）通过 `@ohos.data.preferences` 持久化，存储名 `quiz_settings`。
- 错题阈值在 `DatabaseService` 内有内存缓存（`_autoRemoveThreshold`），由 `loadThreshold` 在 DB 初始化时异步加载，`syncAutoRemoveThreshold` 在设置页修改时同步。
- 注意：设置页偏好 key（如 `autoRemove`）与 `DatabaseService` 内部偏好 key（`auto_remove_threshold`）各自独立维护，设置页修改阈值时同时调用 `syncAutoRemoveThreshold` 确保答题逻辑即时生效。

### 11.11 并发与流式处理

- `BackupService.exportBackup` 使用 `mapBatched` 分批并发拉取各题库题目与各会话答题记录（批上限 8，兼顾速度与内存/调度压力），提升多题库场景下的导出速度。
- `importBackup` 使用 `util.TextDecoder.decodeWithStream` 流式解码，避免按字节切分破坏多字节字符。
- `ZipUtils.decodeUtf8` 同样使用流式解码，规避 `String.fromCharCode` 的 O(n²) 性能问题与多字节边界解析失败。

### 11.12 资源管理

- 颜色与字符串通过 `resources/base/element/` 下的 `color.json` / `string.json` 集中管理。
- 代码中通过 `$r('app.color.xxx')` / `$r('app.string.xxx')` 引用。
- 应用图标/启动图标通过 `module.json5` 中 `$media:icon` / `$media:startIcon` 引用。

---

> 本文档基于项目源码静态分析生成，反映当前代码库的实际结构与实现（采用 Repository 分层模式）。如代码发生重大变更，请同步更新本文档。