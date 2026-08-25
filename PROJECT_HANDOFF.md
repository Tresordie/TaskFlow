# PROJECT_HANDOFF.md — TaskFlow

> 本文档是 AI 模型接力开发的交接文档（活文档）。**接班模型必须先读本文档再动手改代码。**
> 最后更新：2026-08-25 · 当前版本 **v1.4.98**

---

## 0. 快速上手（TL;DR）

- **项目**：TaskFlow —— Flutter Windows 桌面任务管理应用，面向硬件测试工程师（NPI 电动自行车项目）的个人任务/日志/周报工具。
- **位置**：`outputs/taskflow/`（工作区根 = `c:\Users\Administrator\.qoderworkcn\workspace\mrtw67znp8zrkqp4`）。
- **跑起来**：`cd outputs/taskflow && flutter run -d windows`（或 `flutter build windows --release` 后运行 `build\windows\x64\runner\Release\taskflow.exe`）。
- **发版闭环（每次变更必做）**：升版本（`pubspec.yaml` + `lib/core/version.dart` 的 `kAppVersion` **必须同步**）→ `flutter test`（166 个）→ 构建 → `git commit` → **显式单 URL 双推** GitHub + Gitee → `Compress-Archive` 打包 zip 到 `outputs/` → 启动 exe 验证。
- **最高危三条**：① Isar 嵌入对象字段冻结（见禁忌 9.1）；② 禁用全局 SelectionArea（9.2）；③ 杀进程后立即构建会"拒绝访问"，等 15–25 秒重试（8.1）。

---

## 1. 项目概述与目标

用户是一名 NPI 硬件/测试工程师，用 TaskFlow 管理任务、记录执行日志（Execution Log）、写工作日志（Work Log）、按周/月生成 AI 周报（Reports）、看日历/活动热力图，并通过 Google Drive 文件夹镜像跨设备同步数据（含附件）。

核心价值诉求：**快速记录、无损渲染（Markdown 可选择可复制）、AI 深度总结、跨设备同步可靠**。

迭代风格：用户每次提 1–3 个具体需求（常附截图），期望当轮完成构建 + 打包 + 双远程推送 + 启动验证。**重复发送相同消息 = 催促**，应优先完成手头流程。

---

## 2. 技术栈与环境

| 项 | 值 |
|---|---|
| Flutter | 3.44.7（stable，Windows 桌面） |
| 语言 | Dart（无需空安全迁移，全项目 null-safety） |
| 状态管理 | flutter_riverpod（StateNotifierProvider 为主） |
| 本地数据库 | Isar 3.1.0（NoSQL，文件存于用户 Documents） |
| 路由 | go_router |
| 持久化设置 | shared_preferences |
| AI | OpenAI 兼容 API（用户在 Settings 配置 baseUrl/apiKey/model；支持推理模型流式） |
| 字体 | assets/fonts/ 内置 Inter + HarmonyOS Sans SC（约 25MB，发布包 ~32MB） |
| 同步 | Google Drive for Desktop 文件夹镜像（无 API，纯文件复制） |

环境：Windows 22H2 + PowerShell 7。密钥（AI API Key、Google Drive 路径）均存 shared_preferences，代码库无明文密钥。

---

## 3. 目录结构与关键文件

```
outputs/taskflow/
├── lib/
│   ├── main.dart                 # 启动：AttachmentService.init() 预热附件目录
│   ├── app/                      # TaskFlowApp（主题/字体/字号缩放注入）、router、AppShell 之外的壳
│   ├── core/
│   │   ├── theme/app_colors.dart # ThemePalette 定义（13 个主题调色板）+ 遗留硬编码别名
│   │   ├── theme/app_theme.dart  # AppThemeMode 枚举（label/labelZh/palette/brightness）+ buildTheme
│   │   ├── markdown/             # html_sanitize（HTML混入清洗）、line_breaks、rich_markdown、latex
│   │   └── version.dart          # kAppVersion 常量（仅 Settings About 显示）
│   ├── data/
│   │   ├── models/task.dart      # Task + 嵌入对象 SubStep/ExecutionEntry/Attachment/SubStepOrigin
│   │   ├── models/task_snapshot.dart  # 手写快照序列化（拖拽可逆用）
│   │   ├── repositories/task_repository.dart  # 含拖拽合并/提取逻辑
│   │   └── services/             # sync_service（Drive同步）、attachment_service、backup_service、ai_service、report_service
│   ├── providers/                # task_providers、theme_provider、font_provider、typography_provider、work_log_provider、sync_providers、ai_provider
│   └── presentation/
│       ├── shared/               # app_markdown_body（块级渲染）、selectable_markdown_body（整篇可选）、markdown_editor_field（Write/Preview 输入）、markdown_input
│       ├── task_detail/          # task_detail_screen、execution_log_widget（内联编辑）
│       ├── reports/              # reports_screen（分栏编辑器 + AI 生成）
│       ├── work_log/ calendar/ heatmap/ ai_parse/ settings/
├── test/                         # 15 个测试文件，166 个测试
└── pubspec.yaml                  # version 字段与 kAppVersion 必须同步
```

发布包与源码同级：`outputs/TaskFlow-vX.Y.Z-windows-x64.zip`（v1.0.0 → v1.4.98 全保留）。

---

## 4. 运行 / 构建 / 测试 / 部署

```powershell
cd outputs\taskflow
flutter test                                    # 166 个，约 15–20 秒
dart analyze lib                                # 要求 0 error
flutter build windows --release                 # 约 60–100 秒

# 发布（PowerShell，逐条执行；&& 链式可用但变量赋值不要混入）
git add -A; git commit -m "v1.4.X: <英文摘要>"
git push https://gitee.com/simonyuan2019/TaskFlow.git master
git push https://github.com/Tresordie/TaskFlow.git master   # 偶发超时，重试即可
cd ..
Compress-Archive -Path "taskflow\build\windows\x64\runner\Release\*" -DestinationPath "TaskFlow-v1.4.X-windows-x64.zip" -Force
Start-Process -FilePath "taskflow\build\windows\x64\runner\Release\taskflow.exe" -WorkingDirectory "taskflow\build\windows\x64\runner\Release"
```

**版本纪律**：每次发版同时改 `pubspec.yaml` 的 `version: 1.4.X+1` 和 `lib/core/version.dart` 的 `kAppVersion = '1.4.X'`（v1.4.63 曾落后 29 个版本的事故）。

---

## 5. 架构与数据流

- **状态**：Riverpod。`taskListProvider`（任务 CRUD/拖拽/日志）、`themeModeProvider`、`fontProvider/fontScaleProvider/fontWeightProvider`、`contentTypographyProvider/inputTypographyProvider`（内容/输入字体分离设置）、`syncProvider`。
- **数据模型**：Isar Collection `Task`，内嵌 `subSteps`、`executionLog`、`attachments`、`subStepOrigins`（拖拽快照）。**嵌入对象字段冻结**（见 9.1），新元数据放 Task 级增量列表。
- **渲染架构（最终定型，勿再改动方向）**：
  - 已保存内容（Notes/Records/Summaries/预览）→ `SelectableMarkdownBody`：整篇单一 `SelectableText.rich`，跨行拖选 + 右键菜单（Select all / Copy / Copy as Markdown）。
  - 块级 Markdown（Reports 预览等）→ `AppMarkdownBody`（MarkdownBody + 自定义扩展，**无 InlineHtmlSyntax**，因此 `<br>` 在表格单元格中会渲染为字面文本——这是 v1.4.88 Progress Details 改清单版式的原因）。
  - 输入区 → `MarkdownEditorField`（Write/Preview 切换，预览样式与保存后渲染一致，WYSIWYG）。
- **报告生成**：`report_service.dart` —— `formatTaskData` 把任务描述（截断 2000 字）+ **全部执行日志**（期内条目为主体，期前条目标注 `(earlier context)`，期前文本每任务上限 12000 字符）喂给 AI；推理模型走流式 `_chatStream`（180 秒块间隔超时，不限总时长）；AI 失败回退确定性模板。输出 5 章节，Progress Details 为"加粗任务标题 + `- ` 清单一行一条"。
- **同步**：`sync_service.dart` —— Google Drive 文件夹镜像。`Sync Now` 两阶段：PHASE 1 Pull（快照合并 + 拉取缺失附件）→ PHASE 2 Push（本地快照 + 附件推回）。附件复制并行 4 路、失败即 `attrib +P` 钉住触发 Drive 下载、轮内 3 秒后重试。启动时路径自愈合（盘符变化自动重定位）。
- **附件**：新附件存相对文件名；`AttachmentService.resolvePathSync` 三级解析（原路径→相对→basename）；剪贴板粘图经 PowerShell 5.1 `Clipboard.GetImage()`。

---

## 6. 核心业务规则与约定

1. **双远程同步**：每次提交必须推 GitHub（`https://github.com/Tresordie/TaskFlow.git`）+ Gitee（`https://gitee.com/simonyuan2019/TaskFlow.git`），显式单 URL 分别推，不用 `origin` 多 URL。
2. **版本显示**：只在 Settings → About 显示 `kAppVersion`；侧边栏不显示版本号（用户明确要求，v1.4.93）。
3. **主题体系**：13 个主题 = 4 浅色（indigoLight/freshGreen/sunsetOrange/lavenderPurple）+ 1 暗色（dark）+ 8 Catppuccin（Latte×2 浅色、Frappé/Macchiato/Mocha×2 暗色）。已删除：oceanBlue、sakuraPink、blueDark、purpleDark。主题按 `mode.name` 字符串持久化，删除枚举值安全（回退默认）。
4. **报告**：AI 总结必须基于描述+全部日志；技术要点（料号/固件版本/参数/测量值/测试条件/结果/根因）绝不过度压缩，照抄原文；5 章节齐备不可省。
5. **编辑记录**：Execution Log 记录编辑为**输入区内联模式**（v1.4.90）：点编辑 → 内容/类型/附件载入底部输入区，记录高亮 + "Editing" 徽标 → Update 原位更新（保留 uid+时间戳）/ Cancel 取消。编辑对话框已删除。按钮布局：Cancel（描边）左 + Update（主题色）右（v1.4.95 等高等圆角）。
6. **导出同源**：Export.md / Export.html / Email.html 均来自 `s.markdown`；Email 版适配 Gmail（表格布局+内联样式+无 `<style>` 块）。
7. **命名/注释**：代码注释英文为主，版本相关改动注释带 `// v1.4.X:` 前缀。
8. **测试契约**：渲染/格式相关的测试断言是"契约"，改架构必须同步更新断言而不是删测试。

---

## 7. 关键决策记录

| 日期/版本 | 决策 | 理由 |
|---|---|---|
| v1.4.73-77 | 移除全局 SelectionArea，内容区统一 SelectableMarkdownBody | SDK bug：右键时 `_handleRightClickDown` 命中测试失败清空选区 |
| v1.4.78-80 | 拖拽合并/提取用 `SubStepOrigin` 快照（Task 级列表） | SubStep 嵌入对象字段冻结，不能加字段 |
| v1.4.83 | 附件存相对文件名 + 三级解析 | 跨设备路径不同，绝对路径失效 |
| v1.4.84-87 | Drive 同步：附件镜像 + 占位文件不预过滤 + `attrib +P` 钉住 + 路径自愈合 | Drive 云端占位文件 `existsSync()` 为 false，预过滤会永久跳过；盘符重启变化 |
| v1.4.88 | Progress Details 由 `<br>` 表格改为清单版式；AI 喂全部日志 | 应用内 MarkdownBody 不渲染 `<br>`；深度理解需要全量历史 |
| v1.4.90-91 | 编辑对话框 → 输入区内联编辑 + 显式 Update 按钮 | 用户要同一编辑环境；纯快捷键入口不可发现 |
| v1.4.96 | Catppuccin 四风味八主题 | 用户指定色彩体系，官方色值 + WCAG 映射 |
| v1.4.98 | Latte 表面层级反转修正（card>surface>bg）；删 4 主题 | 官方 base/mantle 映射在 light 下发灰；用户精简主题 |

---

## 8. 踩坑记录：问题与解决方案

| # | 现象 | 根因 | 解决 | 预防 |
|---|---|---|---|---|
| 8.1 | `flutter.bat failed to run: 拒绝访问` | 杀应用进程后文件锁未释放 | 等 15–25 秒重试，必成功 | 杀进程后构建前固定 `Start-Sleep 20` |
| 8.2 | GitHub push 超时（21s） | 网络波动，非代码问题 | 显式单 URL 重试 1–3 次 | 不用 `origin` 多 URL 推送；提交本地不丢 |
| 8.3 | Drive 大附件跨设备同步不到 | 云端占位文件 `existsSync()=false` 被预过滤跳过 | 不预过滤源存在性，逐文件尝试复制，失败计 pending 下轮重试 | 任何"复制 if-missing"同步都按目标端判断，不按源端存在性过滤 |
| 8.4 | 30MB 附件同步需多次手动触发 | 占位文件未本地化 | 复制失败时 `attrib +P -U <path>` 钉住触发下载 + 3 秒后轮内重试 | 见 8.3 |
| 8.5 | Drive 路径重启后失效 | 盘符/挂载点变化 | 启动与同步前扫描 D–Z 盘，按 `TaskFlow` 标记重定位 + 6 秒轮询等挂载 | 持久化路径用前必须校验存在性并自愈合 |
| 8.6 | kAppVersion 落后 29 个版本 | 发版脚本只改 pubspec | 双处同步（已入长期记忆） | 每次升版检查两处 |
| 8.7 | widget 测试 RenderFlex 溢出 | 侧边栏加版本号后窄测试窗口溢出 | `Flexible` + ellipsis 包裹 | 往固定宽度容器加元素要考虑窄屏 |
| 8.8 | 测试访问 Riverpod provider 抛异常 | 裸 MaterialApp 无 ProviderScope | helper 内 `try { ProviderScope.containerOf } catch { 降级 }` | 跨测试复用的 context 查找必须容错 |
| 8.9 | 单引号 raw string 正则报语法错 | `r'...\'...'` 中 `\'` 提前终止字符串 | 用三引号 `r'''...'''` | 含单引号的正则一律三引号 |
| 8.10 | Markdown 表格多行单元格导出破碎 | 单元格内真换行打断管道行 | `_normalizeMultilineTableRows` 合并 `<br>`；导出用原始 AI markdown 除非用户真编辑 | 表格单元格内容变更必须过 normalizer |
| 8.11 | 报告内 `<br>` 显示为字面文本 | AppMarkdownBody 无 InlineHtmlSyntax（故意，防止吞 `<font>`） | 内容版式避免依赖 `<br>`（Progress Details 改清单） | 不要为表格换行重新引入 InlineHtmlSyntax |
| 8.12 | PowerShell `&&` 链中变量赋值报错 | sandbox 包装层解析差异 | 分号分步执行，或纯 `&&` 无赋值 | 复杂流程分多条命令 |
| 8.13 | DeleteFile 工具在 Windows 偶发静默失效 | 工具已知问题 | 用 `Remove-Item -Recurse -Force` 并验证结果 | 删除后 `Get-ChildItem` 复核 |

---

## 9. 禁忌清单

1. **禁改 Isar 嵌入对象字段**（SubStep/ExecutionEntry/Attachment）——schema 冻结。新元数据放 Task 级增量列表（参考 `subStepOrigins` 模式）并跑 `dart run build_runner build` 重新生成 `task.g.dart`。
2. **禁加全局 SelectionArea**（AppShell/MaterialApp builder 层）——右键清空选区 + 劫持嵌套 SelectableText。
3. **禁重新引入 InlineHtmlSyntax** 到 AppMarkdownBody——会吞掉 `<font>` 富文本标签。
4. **禁在侧边栏显示版本号**（用户明确要求移除，仅 Settings About）。
5. **禁恢复已删除主题**：oceanBlue、sakuraPink、blueDark、purpleDark（用户要求删除）。
6. **禁把 Latte 表面映射回官方 base/mantle 顺序**——light 模式必须 card > surface > bg。
7. **禁用 `git push origin`**（多 push URL 超时即整体失败）。
8. **禁静默吞保存错误**——所有持久化失败必须 snackbar 告知用户。
9. **禁依赖 Ctrl+Enter 等快捷键作为唯一操作入口**——用户曾找不到保存按钮（v1.4.91 教训：显式按钮必须可见）。
10. **禁删测试代替改测试**——断言是契约，架构变更时更新断言。

---

## 10. 当前进度与下一步计划

**已完成（近期）**：
- ✅ v1.4.98：Latte 清晰度修复 + 删除 4 主题（13 主题）
- ✅ v1.4.96-97：Catppuccin 四风味八主题体系（官方色值 + WCAG 映射）
- ✅ v1.4.94-95：编辑态 Update/Cancel 按钮美化
- ✅ v1.4.90-93：Execution Log 内联编辑、版本号仅 About 显示
- ✅ v1.4.88-89：报告全量日志输入 + Progress Details 清单版式 + 期前上限 12000 字
- ✅ v1.4.85-87：字体排版双 Provider、可调节图片预览、Drive 路径自愈合 + 附件钉住下载
- ✅ 双远程均已同步至 `4d401ed`（v1.4.98）

**进行中**：无（等待用户新需求）

**待办/已知局限**：
- `app_colors.dart` 底部遗留硬编码别名（lightBg/darkBorder 等）被部分代码以 `isDark ? darkX : lightX` 直接引用，不跟随当前主题色相——改浅色主题时需同步这些别名。
- GitHub 推送偶发超时（环境问题，重试即可）。
- Google Drive 同步无文件冲突合并策略（附件为不可变 uuid 文件天然无冲突；快照为 merge-by-uid）。

---

## 11. 给接手机型的建议

1. **先读后动**：顺序 = 本文档 → `lib/core/theme/` → `lib/presentation/shared/`（渲染三件套）→ `lib/data/services/`。
2. **每轮交付完整闭环**：改码 → analyze → test → 双处升版 → 构建（记得杀进程后等 20 秒）→ 提交 → 双推 → 打包 → 启动。用户期待一轮完成。
3. **用户对视觉细节敏感**：按钮排布、亮度、清晰度、留白都可能被点名；改动前先想"桌面端惯例"（主操作居右、等高对称、显式入口）。
4. **测试是安全网**：166 个测试覆盖渲染契约与报告格式，改前先跑，改后必过。
5. **长期记忆系统里有大量项目约定**（主题、报告规范、推送纪律等），接手时先查。
6. **不要主动创建文档文件**（包括本文件的更新除外）——用户未要求时不写 README。

---

## 12. 交接记录

| 日期 | 交班模型 | 接班模型 | 本次会话主要变更 |
|---|---|---|---|
| 2026-08-25 | Qoder（本会话，v1.4.85→v1.4.98） | 待定 | 字体排版设置、可调节图片预览、编辑对话框粘图、Drive 同步加固（两阶段/占位文件/路径自愈合）、报告全量日志+清单版式、内联编辑流程、Catppuccin 主题体系、主题精简与 Latte 清晰度修复 |
