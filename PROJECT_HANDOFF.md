# PROJECT_HANDOFF.md — TaskFlow

> 本文档是 AI 模型接力开发的交接文档（活文档）。**接班模型必须先读本文档再动手改代码。**
> 最后更新：2026-09-28 · 当前版本 **v1.12.27**（奶油玻璃 dashboard 主题 + onPrimary 机制；13 款主题；303 测试；已发版双推）

---

## 0. 快速上手（TL;DR）

- **项目**：TaskFlow —— Flutter Windows 桌面任务管理应用，面向硬件测试工程师（NPI 电动自行车项目）的个人任务/日志/周报工具。
- **位置**：`outputs/taskflow/`（工作区根 = `c:\Users\Administrator\.qoderworkcn\workspace\mrtw67znp8zrkqp4`）。
- **跑起来**：`cd outputs/taskflow && flutter run -d windows`（或 `flutter build windows --release` 后运行 `build\windows\x64\runner\Release\taskflow.exe`）。
- **发版闭环（每次变更必做）**：升版本（`pubspec.yaml` + `lib/core/version.dart` 的 `kAppVersion` **必须同步**）→ `flutter test`（297 个）→ 构建 → `git commit` → **显式单 URL 双推** GitHub + Gitee → `Compress-Archive` 打包 zip 到 `outputs/` → 启动 exe 验证。
- **最高危五条**：① Isar 嵌入对象字段冻结（见禁忌 9.1）；② 禁用全局 SelectionArea（9.2）；③ 杀进程后立即构建会“拒绝访问”，等 15–25 秒重试（8.1）；④ 可能出现中文的 TextStyle 禁只设 `fontFamily`，必须带 `FontStack` 回退链（9.11）；⑤ 两渲染链共用的 `GfmExtensions.prepare` 管线（多行公式展平 → 表格行归一 → 硬换行硬化）顺序不可乱改，表格行/alert 起始行/`$$` 行豁免硬化（8.19-8.20）。

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
| 字体 | assets/fonts/ 内置：Manrope 可变字体（拉丁，0.16MB）+ MiSans R/M/SB（中文，22.5MB）+ HarmonyOS Sans SC Regular（中文兜底）；授权声明随包 `assets/fonts/FONT_LICENSES.md`；字体合计 30.5MB，发布包 35.8MB |
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
│   │   ├── theme/font_stack.dart # 中英混排链单一事实源（v1.5.2，拉丁/中文/回退链常量）
│   │   ├── markdown/             # html_sanitize（HTML混入清洗）、line_breaks（硬换行硬化+结构行豁免）、rich_markdown（含上下标语法）、latex_support（严格定界+多行展平）、gfm_extensions（alerts 大小写敏感语法/任务清单 checkbox hoist/`<br>`/prepare 管线）、table_support（多行行归一+列宽）
│   │   └── version.dart          # kAppVersion 常量（仅 Settings About 显示）
│   ├── data/
│   │   ├── models/task.dart      # Task + 嵌入对象 SubStep/ExecutionEntry/Attachment/SubStepOrigin
│   │   ├── models/task_snapshot.dart  # 手写快照序列化（拖拽可逆用）
│   │   ├── repositories/task_repository.dart  # 含拖拽合并/提取逻辑
│   │   └── services/             # sync_service（Drive同步）、attachment_service、backup_service、ai_service、report_service
│   ├── providers/                # task_providers、theme_provider、font_provider、typography_provider、board_card_style_provider、work_log_provider、sync_providers、ai_provider
│   └── presentation/
│       ├── shared/               # app_markdown_body（块级渲染）、selectable_markdown_body（整篇可选）、markdown_editor_field（Write/Preview 输入）、markdown_input
│       ├── task_detail/          # task_detail_screen、execution_log_widget（内联编辑）
│       ├── reports/              # reports_screen（分栏编辑器 + AI 生成）
│       ├── work_log/ calendar/ heatmap/ ai_parse/ settings/
├── test/                         # 29 个测试文件，300 个测试（含 extended_markdown/selectable_spacing/font_upgrade/gfm_extensions/theme_palette/kanban_board/board_card_style 契约）
└── pubspec.yaml                  # version 字段与 kAppVersion 必须同步；fonts + FONT_LICENSES.md 声明
```

发布包与源码同级：`outputs/TaskFlow-vX.Y.Z-windows-x64.zip`（v1.0.0 → v1.5.2 全保留）。

---

## 4. 运行 / 构建 / 测试 / 部署

```powershell
cd outputs\taskflow
flutter test                                    # 300 个，约 30–40 秒
dart analyze lib                                # 要求 0 error（task.g.dart 的 experimental 警告为既有）
flutter build windows --release                 # 约 60–110 秒

# 发布（PowerShell，逐条执行；&& 链式可用但变量赋值不要混入）
git add -A; git commit -m "v1.4.X: <英文摘要>"
git push https://gitee.com/simonyuan2019/TaskFlow.git master
git push https://github.com/Tresordie/TaskFlow.git master   # 偶发超时，重试即可
cd ..
Compress-Archive -Path "taskflow\build\windows\x64\runner\Release\*" -DestinationPath "TaskFlow-v1.4.X-windows-x64.zip" -Force
Start-Process -FilePath "taskflow\build\windows\x64\runner\Release\taskflow.exe" -WorkingDirectory "taskflow\build\windows\x64\runner\Release"
```

**分发打包（v1.9.2 起固定步骤）**：Flutter Release 产物不含 VC++ 运行时，干净系统会报缺 `VCRUNTIME140.dll`——打包前必须把 4 个 DLL 复制到 Release 目录（来源 `C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Redist\MSVC\14.30.30704\x64\Microsoft.VC143.CRT\`：`msvcp140.dll`、`msvcp140_1.dll`、`vcruntime140.dll`、`vcruntime140_1.dll`），并确认 `使用说明.txt`（解压即用/SmartScreen 应对/数据位置/迁移方法）在包根目录；若 `build/` 被清空重建，这两个动作都要重做。

**版本纪律**：每次发版同时改 `pubspec.yaml` 的 `version: 1.5.X+1` 和 `lib/core/version.dart` 的 `kAppVersion = '1.5.X'`（v1.4.63 曾落后 29 个版本的事故）。

---

## 5. 架构与数据流

- **状态**：Riverpod。`taskListProvider`（任务 CRUD/拖拽/日志）、`themeModeProvider`、`fontProvider/fontScaleProvider/fontWeightProvider`、`contentTypographyProvider/inputTypographyProvider`（内容/输入字体分离设置）、`syncProvider`。
- **数据模型**：Isar Collection `Task`，内嵌 `subSteps`、`executionLog`、`attachments`、`subStepOrigins`（拖拽快照）。**嵌入对象字段冻结**（见 9.1），新元数据放 Task 级增量列表。
- **渲染架构（最终定型，勿再改动方向）**：
  - 已保存内容（Notes/Records/Summaries/预览）→ `SelectableMarkdownBody`：整篇单一 `SelectableText.rich`，跨行拖选 + 右键菜单（Select all / Copy / Copy as Markdown）。
  - 块级 Markdown（Reports 预览等）→ `AppMarkdownBody`（MarkdownBody + 自定义扩展，**无 InlineHtmlSyntax**；`<br>` 由窄义 `BrSyntax` 支持，仅限 br 标签，见 8.11/8.21）。
  - 输入区 → `MarkdownEditorField`（Write/Preview 切换，预览就是 SelectableMarkdownBody，WYSIWYG）。
  - 两链共用：语法注册集中在 `lib/core/markdown/gfm_extensions.dart`（`GfmExtensions.blockSyntaxes`/`inlineSyntaxes()`/`prepare()`）；`prepare` 管线 = flattenDisplayMath（多行 `$$` 并一行）→ normalizeMultilineTableRows（AI 断行单元格合并 `<br>`）→ hardenMarkdownLineBreaks（可选，表格行/`> [!TYPE]` 起始行/`$$` 行豁免）。
- **报告生成**：`report_service.dart` —— `formatTaskData` 把任务描述（截断 2000 字）+ **全部执行日志**（期内条目与近 7 天条目为主体完整投喂，超一周的旧条目标注 `(older than 7 days — context only)`，旧文本每任务上限 12000 字符）喂给 AI；推理模型走流式 `_chatStream`（180 秒块间隔超时，不限总时长）；AI 失败回退确定性模板。输出 5 章节；v1.5.6 起仪表盘 Headline 为 `<br>` 列表（≤3 条）、执行摘要无 sub-step 比例；**v1.9.3 报告总结优化（用户三需求）**：① 执行摘要 In Progress 每任务一行=加粗标题+" — "+一句话总结（无缩进要点）；② 进度明细近因聚焦改为**近一周（7 天）**，更早条目压缩为"早期背景："一句历史总结，详情条目对任务做详细描述；③ 下期计划只含未完成任务（计划中/进行中/阻塞逾期）、**每任务一行禁止分解**为子任务行。
- **同步**：`sync_service.dart` —— Google Drive 文件夹镜像。`Sync Now` 两阶段：PHASE 1 Pull（快照合并 + 拉取缺失附件）→ PHASE 2 Push（本地快照 + 附件推回）。附件复制并行 4 路、失败即 `attrib +P` 钉住触发 Drive 下载、轮内 3 秒后重试。启动时路径自愈合（盘符变化自动重定位）。
- **扩展 Markdown（v1.5.0）**：两侧渲染器支持脚注（`[^1]`+定义附录）、上标 `^x^`/下标 `~x~`（0.7× 小字号，保整篇可选）；SelectableMarkdownBody 的 `==高亮==`/`++下划线++`/`<font>` 样式不再丢失。**关键顺序**：自定义 rich 语法必须排在 `StrikethroughSyntax` 之前（包的删除线会贪婪吞单 `~`，见 8.14）。Mermaid 扩展仍不做（9.12）；**LaTeX 已在 v1.5.3 落地**（用户重提后解除）。
- **GFM 四能力（v1.5.3）**：① 表格：AppMarkdownBody 走 flutter_markdown 0.7.7 原生 Table（表头加粗/主题色边框/单元格 padding 由 styleSheet merge 注入），可选链渲染为等宽对齐纯文本列（CJK 双宽计宽，`table_support.displayWidth/padCell`）；② 任务清单 `- [ ]`/`- [x]`：自定义语法把 `<input>` 提升到 `<li>` 首子节点（包默认插在 `p` 里会被 flutter_markdown 丢弃），AppMarkdownBody 经 `checkboxBuilder` 渲染 ☐/☑，可选链用字形替换项目符号（☑ 主题色，只读无交互）；③ GFM Alerts：`GfmAlertSyntax`（大小写敏感，区别于包内 `AlertBlockSyntax`），输出 `div.markdown-alert-*` + `data-alert`/`data-source` 属性；AppMarkdownBody 用 `_DivDispatchBuilder` 渲染主题化容器（左色条+淡背景+大写类型标签，内容经嵌套 AppMarkdownBody 重渲染——flutter_markdown 的 builder 拿不到已构建子节点，只能靠 data-source 重建），可选链降级为着色类型标签 + `│ ` 槽线文本；普通 `>` 引用行为不变；五色语义色集中在 `AppColors.alertAccent/alertBackground`（亮/暗双套，禁散落硬编码）；④ LaTeX：仅 `$...$` 与 `$$...$$`（不解析 `\( \)`/`\[ \]`），严格定界防货币误判（开 `$` 后非空白、闭 `$` 前非空白、负向环视避 `$$`），多行 `$$` 块由 `flattenDisplayMath` 展平；AppMarkdownBody 用 `Math.tex`（失败回退原文红斜体）；可选链行内/块级均以 `WidgetSpan` 嵌入（**已知降级：公式不参与文字选区、复制时丢失**）；流式期间不完整公式不匹配语法而显示原文，流结束后重解析自动渲染，无需特判。
- **块间距契约（v1.5.1）**：SelectableMarkdownBody 顶层块分隔符按上下文决定——标题紧贴后续块（单 `\n`）、段落直接引出列表不留空行、真实段落保留一个空行；禁止连续多空行。契约测试 `selectable_spacing_test.dart`（4 项）。旧的统一 `\n\n` 会产生"多余空行"观感。
- **字体栈（v1.5.2）**：混排链单一事实源 `lib/core/theme/font_stack.dart`（FontStack：latin='Manrope', cjk='MiSans', fallback 链含 Segoe UI Emoji）。接入点：app_theme.dart（默认栈）、app.dart `_applyFont`（google 下载分支 + 内置配对分支）、typography_provider 双链路（family 覆盖必同步写回退链）。默认字体 = interMisans（Inter×MiSans，v1.9.0 起为应用默认；旧 system 预设已随精简删除，持久化键 `settings.fontId`，未知 id 含旧 'system' 安全回退默认；离线时 Inter 下载失败经回退链 MiSans→HarmonyOS Sans SC 兜底）。
- **附件**：新附件存相对文件名；`AttachmentService.resolvePathSync` 三级解析（原路径→相对→basename）；剪贴板粘图经 PowerShell 5.1 `Clipboard.GetImage()`。

---

## 6. 核心业务规则与约定

1. **双远程同步**：每次提交必须推 GitHub（`https://github.com/Tresordie/TaskFlow.git`）+ Gitee（`https://gitee.com/simonyuan2019/TaskFlow.git`），显式单 URL 分别推，不用 `origin` 多 URL。
2. **版本显示**：只在 Settings → About 显示 `kAppVersion`；侧边栏不显示版本号（用户明确要求，v1.4.93）。
3. **主题体系**：13 个主题（v1.12.27）= 2 浅色（warmSand 暖沙/inkBlue 黛蓝）+ 2 暗色基础（dark/nordNight）+ **看板着色系 2 款**（notionBoard 墨板/midnightBoard 午夜看板，列底按语义 accent 着色）+ 6 Catppuccin 暗色（Frappe 木槿紫/蓝晶、Macchiato 木槿紫/青碧、Mocha 木槿紫/薰衣草）+ **glassDashboard 奶油玻璃**（v1.12.27，暖炭玻璃阶梯+奶油 primary #EFE9DA+深炭 onPrimary——全目录唯一"深字压浅 accent"的主题）。v1.12.21 删除奶油/珍珠看板（v1.12.20 已让全部浅色看板化，独立的浅色看板款冗余）；v1.12.25 删除可可看板。已删除：v1.12.17 用户点名删 11 款（indigoLight/freshGreen/sunsetOrange/lavenderPurple/celadon/dustyRose/mintFresh/clearSky/peachCream/双 Latte）；**默认主题改为 inkBlue 黛蓝**（原默认 freshGreen 已删）。已删除：oceanBlue、sakuraPink、blueDark、purpleDark（v1.4.98）及 v1.7.0 曾上线的 espresso/deepSea/aubergine（v1.8.0 用户实测后要求删除）。主题按 `mode.name` 字符串持久化，删除枚举值安全（回退默认）；枚举按组插入（浅接 warmSand 后、深接 nordNight 后），Settings 列表/亮度/GFM alert 色自动适配。v1.12.27 起 ThemePalette 携带 `onPrimary`（压 primary 的前景色，默认白）——白字压 primary 的组件一律读它，不得硬编码 Colors.white。
4. **报告**：AI 总结必须基于描述+全部日志；技术要点（料号/固件版本/参数/测量值/测试条件/结果/根因）绝不过度压缩，照抄原文；5 章节齐备不可省。
5. **编辑记录**：Execution Log 记录编辑为**输入区内联模式**（v1.4.90）：点编辑 → 内容/类型/附件载入底部输入区，记录高亮 + "Editing" 徽标 → Update 原位更新（保留 uid+时间戳）/ Cancel 取消。编辑对话框已删除。按钮布局：Cancel（描边）左 + Update（主题色）右（v1.4.95 等高等圆角）。
6. **导出同源**：Export.md / Export.html / Email.html 均来自 `s.markdown`；Email 版适配 Gmail（表格布局+内联样式+无 `<style>` 块）。
7. **命名/注释**：代码注释英文为主，版本相关改动注释带 `// v1.X.Y:` 前缀。
8. **测试契约**：渲染/格式相关的测试断言是"契约"，改架构必须同步更新断言而不是删测试。
9. **中英混排铁律（v1.5.2）**：任何可能出现中文的 TextStyle 禁止只设 `fontFamily`，必须携带 `FontStack.fallback`/`pairingFallback()` 回退链；新增字体接入必须走现有双 Provider + Settings 自动 UI，禁另起炉灶；嵌入字体必须可再分发（OFL 或厂商免费商用），授权声明进 `FONT_LICENSES.md` 随包。
10. **预设删除/替换安全模式**：字体/主题按 id/name 字符串持久化；删选项靠"未知值回退默认"保安全；替换选项保留原 id 使存量选择无缝迁移。

---

## 7. 关键决策记录

| 日期/版本 | 决策 | 理由 |
|---|---|---|
| v1.12.27 | **奶油玻璃 dashboard 主题（glassDashboard）+ onPrimary 机制**（用户："参考图片做一个dashboard主题"——深色毛玻璃 dashboard 参考图，暖炭玻璃面板+奶油色 accent 胶囊/按钮，奶油底上是深炭色文字）：① **新调色板 glassDashboard**——bg #2E2B28（深暖灰画布）→ surface #3B3835 → card #4A4640（对应参考图玻璃层层浮起），文字 #F3F0E9/#BCB6AB，primary **#EFE9DA 奶油色**（选中胶囊/选中日/确认按钮），枚举追加为第 13 款（按 `mode.name` 持久化，追加安全）；② **ThemePalette 新增可选 `onPrimary` 字段**（默认白色——其余 12 款零影响；奶油主题设深炭 #33302B，对比度≈11:1），接入 ColorScheme.onPrimary/onSecondary + ElevatedButton 前景；③ **白字压 primary 的硬编码全部改读 onPrimary**——Calendar 选中日徽章/日期数字/任务点/选中格上 `_DuePill`、Settings 主题卡+字体卡对勾、About 渐变图标、6 处按钮 loading spinner（Settings/AI Prompts/AI Parse/Reports/Work Log）；**保持白色**的场景：success 绿按钮（AppColors.success 底，非 primary）、执行日志状态色圆圈（语义色底）、图片查看器关闭按钮（黑色遮罩底）。测试：主题数 12→13、暗色分组+签名色+onPrimary 契约（其余恒白/奶油必深） | 参考图的精髓是"奶油底深字"——与全目录"白字压彩底"相反，逐处改白字会漏且脆；正解=把 on-accent 前景色变成调色板一等公民（Material 本就有 onPrimary 槽位），默认值保住向后兼容；spinner 白字是隐形雷（奶油按钮上白圈直接消失）；主题持久化按 name 所以追加枚举不破坏已存偏好 |
| v1.12.26 | **Calendar 日期格实体瓷砖质感**（用户："Calendar页面中日期视觉感，质感以及立体感更强"）：`_DayCell` 重构为**四层质感模型**——①**顶面受光渐变**（浅色主题 card≈surface 渐变不可见，手动拉开：顶部向纯白 lerp 50%、底部向 onSurface lerp 4.5%；深色主题用 cardTheme.color→surface 天然色阶）；②**镜面高光**——Stack 内 Positioned(1) 白色顶部渐变 sheen（inset 1px 不盖边框，圆角随外框 -2），强度 0（周末）→0.05→0.10（hover）→0.12（today）→0.26（选中）；③**斜面边框**+**层叠投影**（选中=primary 光晕 blur12 y4 + 贴地接触影双层）；强度随 静止→hover→today→selected 递进；④**周末反转渐变**（上深下浅=凹陷井）；⑤**今日/选中日 22px 圆形日期徽章**（Apple Calendar 锚点，选中=白 22% 底+白边，今日=primary 14% 底+主色边），数字 13.5px height1.0 w600/w800；格间距 margin 2→3 强化"独立按键"分块；Container padding 移入 Stack 内层 Positioned.fill（sheen 需贴边框）。验证轮：临时 golden 测试（浅色选中+hover / 深色范围模式，FontLoader 加载 Manrope/MiSans）2x 放大逐格目检后删除 | 浅色主题 card 与 surface 都是近白色，靠默认色阶做不出立体感——必须手动构造明暗；sheen 是廉价高光手法（1 个渐变=玻璃瓷釉感）；周末反渐变让工作日/休息日从"色块差异"升级为"凸起/凹陷"触感隐喻；全部状态分支都给 gradient（无 null）让 AnimatedContainer 状态切换时渐变平滑插值；golden 目检 catching 了浅色渐变不可见问题（第一版 card→surface 渐变在 inkBlue 下纯隐形） |
| v1.12.25 | **删除可可看板 + Calendar/Activity 精修**（用户："①删除主题：可可看板；②Calendar 改进美观/质感/立体感；③Activity 任务状态显示卡的美观/质感/立体感"）：① **cocoaBoard 五处同步删除**（枚举/标签/palette/brightness/调色板+boardTinted 成员），剩 **12 款**（2 浅+3 暗基础+2 看板着色+5 Catppuccin）；② **Calendar**——月份切换器从裸控件改为**居中胶囊工具栏**（surface 底+发丝线+投影，标题 titleMedium w600），日面板头部加**页面级 accent 竖条+主色 10% 圆形计数徽章**（数量从文字行拆出）；③ **Activity `_StatCard` KPI 化**——新增 `accentColor` 参数（Today=primary/Completed=success/Total=info），**左渐变 accent 条**（同 TaskListCard 配方）+ accent 10% 图标章 + **accent 色数值**（w800）+ 10px 大写字距标签；IntrinsicHeight 内置（stretch Row 在页面 Column 的无界子高度下会塌缩，同 v1.12.24 教训）；移除 v1.12.23 遗留的页面级 `_buildLegend`（与网格内 `_HeatLegend` 重复） | 状态卡是"任务状态显示卡"——按语义分色（蓝/绿/蓝）让数值一眼可辨而非全靠主色；IntrinsicHeight 内置进 _StatCard（v1.12.24 教训的肌肉记忆）；旧 _buildLegend 是 v1.12.23 双图例重复的实现遗漏，顺手清除 |
| v1.12.24 | **修 TaskListCard 无界高度塌缩**（用户截图："Calendar 选定日期，日期中的任务列表没有展示"——右侧日面板只见"3 tasks"标题，列表空白）：根因=TaskListCard 内 `Row(crossAxisAlignment: stretch)` 在 **ListView/无界高度容器**里无法解析高度（Timeline 页正常只因外层早有 IntrinsicHeight），stretch 色条+Expanded 内容塌缩为零、任务卡整体不可见。修复=**IntrinsicHeight 内置进 TaskListCard**（三页共用一处修复）；新增 task_list_card_test.dart 两条回归：ListView 内正常渲染无异常、色条高度>10px（塌缩时仅剩 6px 边距） | stretch Row 的宿主高度必须有界；共享组件的布局前提（宿主有界）要内置进组件而不是依赖每个调用点记得包 IntrinsicHeight；IntrinsicHeight 对文本型列表项的开销可接受；Calendar/Activity 两列表同获益 |
| v1.12.23 | **三页任务卡升级 Today 皮肤 + 组件级精修第二轮**（用户："①Timeline ②Calendar ③Activity——任务卡与页面的美观/质感/立体感再增强"；v1.12.16 同款 TaskListCard 曾被回退，本次用户连续三轮提"与 Today 类似/立体感"，确认为正向需求重新引入并升级）：① **TaskListCard 重生**——纯白卡底 + **顶面微亮渐变**（white 5% 顶光，微穹顶质感）+ **左侧渐变 accent 条**（向下淡出 30%，Today 卡签名）+ hover 边框 accent 50%；Timeline `_TimelineItem`（statusColor）/Calendar `_DayTaskItem`/Activity `_ActivityTaskItem`（完成绿/优先级色）三处接入，padding 相应调整（左 0 右 14/12/8）；② **Timeline 脊柱轨道槽**——节点+渐变线放进 18px 宽的 outline 8% 圆角凹槽（"刻进页面的轨道"）；③ **Calendar 周末分组**——周六/周日列加 onSurface 2.5% 微着色（工作日/休息日视觉分块）；④ **Activity 统计卡图标底块**（26px 主色 10% 圆角章，对齐 Today KPI）+ **热力图图例**——Less→四格色阶→More（复刻 _HeatCell 配色），网格右下对齐 | 用户三轮重复诉求=明确正需求，重新引入色条（上次回退疑为打包观感而非色条本身）；顶面微亮是廉价高质感手法（1 行渐变）；轨道槽把"线挂在页面上"变"线嵌在页面里"；热力图图例让强度刻度自解释；组件复用避免三页重复 |
| v1.12.22 | **Timeline/Calendar/Activity 立体感与质感精修**（用户："三页任务卡增加立体感 + 各页面增加美观程度/质感/立体感"）：① **HoverLift 双层静置阴影**——静置=扩散柔光（black 4% blur8 y2）+近距接触影（black 3% blur3 y1）双层 Material elevation 观感，hover 三层（accent 14% blur14 y5 + black 8% blur10 y3 + 接触影）；② **Timeline 时间线脊柱**——节点改"surface 白底圆 + 3px 状态色环 + 4px 彩心 + 状态色光晕（28% blur7）"，连接线由灰色改为**状态色纵向渐变**（32%→8%，圆角），整条脊柱"由内发光"；③ **Calendar**——日期格抽成 `_DayCell` 有状态组件：hover 边框主色+微投影、**今日=主色纵向渐变底（14%→5%）**、选中=主色 30% 投影浮起、星期表头下加发丝分隔线；④ **Activity 热力图**——格子抽成 `_HeatCell`：活动格加**左上径向高光**（white 35% 混入 fill，"发光小凸块"质感），hover 放大 1.25 倍 + 主题色描边，空格保持安静平面 | 立体感=阴影层次而非单层模糊（双层/三层 elevation 是 Material 质感标准做法）；时间线的"发光脊柱"让状态色贯穿节点与连线（状态语义可视化）；日历格 hover 是网格类 UI 的基本可发现性；热力图 hover 放大用 AnimatedScale（120ms）不干扰网格布局；测试断言阴影数 2→3→2 同步 |
| v1.12.21 | **删除奶油/珍珠看板 + 浅色看板透明度修复**（用户："①删除以下主题：奶油看板，珍珠看板；②浅色主题的透明度无法调节"）：① 两款主题五处同步删除（枚举/标签/palette/brightness/调色板），剩 **13 款**（2 浅+3 暗基础+3 看板着色+5 Catppuccin），boardTinted getter 移除该二成员；② **透明度失效根因**=v1.12.20 全浅色看板化后，TaskCard 填充被硬编码为不透明白、列底被硬编码为 accent 10% 着色——两个透明度滑块全部被架空；修复=浅色看板主题下 **Card opacity 滑块直接控制卡片填充**（100%=参考图纯白，调低→列色透入），**Interface Glass 透明度滑块缩放列底着色强度**（`accent 10%×opacity`，玻璃关=满强度参考观感），暗色看板系维持 80% 固定填充 | 上一轮把"参考观感"做成硬编码牺牲了可调性（与 v1.12.8 卡片禁用滑块被投诉同型错误）；正解=滑块调制参考配方的强度而非无视滑块；暗色看板保持定值（用户未提异议且暗色半透明本就好看） |
| v1.12.20 | **全部浅色主题 Notion 化更新**（用户需求"请将所有的浅色主题，基于刚才提供参考的类似notion的dashboard模板图片，进行更新"）：① **暖沙 warmSand 重调**——画布 #FAF6F0→**#F8F6F1** 暖纸、卡 #FDFAF5→**纯白**、边框 #E8DCC8→**#E7E3D8 发丝线**、文字 →Notion 墨 #37352F/#7D786E、主色 #A9713B→**Notion 棕 #9F6B53**（土黄棕在安静底上读作泥色）；② **黛蓝 inkBlue 重调**——画布 #EFF3F8→**#F5F7F9**、卡 #F2F6FA→**纯白**、边框 #D5DEE9→**#E4E8EC**、次文字→#6E7A87，muted 蓝主色三件套保留（本就 Notion 化）；③ **暖沙/黛蓝加入 boardTinted 家族**——至此 4 款浅色主题的 Today dashboard 全部呈现参考图效果（列底按语义 accent 粉彩着色+白卡浮起），boardTinted 家族 5→7（4 浅+3 暗）；④ 遗留色别名 lightX 六项同步跟随黛蓝新值（回归测试锚定） | 参考图的浅色公式=安静近白画布+发丝线+粉彩着色列+白卡+彩色胶囊——四款浅色保留各自色相身份（暖棕/墨蓝/Notion 蓝/Notion 绿）套用同一公式；主色换 Notion 棕是因为原土黄 #A9713B 饱和度过高与发丝线体系打架；boardTinted 加入使浅色全家（不再只有看板主题）获得 dashboard 参考观感 |
| v1.12.19 | **看板主题家族扩至 5 款**（用户给 4 张 Notion 模板截图："参考图片帮我制作一些浅色及深色主题"）：把 v1.12.18 的墨板专属列着色机制泛化为 **boardTinted 主题家族**——`AppThemeMode.boardTinted` getter（switch 通配默认 false），成员=墨板 + 新增 4 款：**奶油看板 creamBoard**（暖纸画布 #FAF8F3 + Notion 蓝 #337EA9，对应奶油色列截图）、**珍珠看板 pearlBoard**（冷珍珠白 #F7F7F8 + Notion 绿 #3D7657，对应白列发丝线截图）、**可可看板 cocoaBoard**（暖近黑 #131210 + Notion 琥珀 #D9730D，对应橄榄/琥珀列暗色截图）、**午夜看板 midnightBoard**（冷板岩黑 #101317 + 深绿 #4E8A67）；TaskBoardScreen/TaskCard 的 notionTint 标志改读 boardTinted。着色配方分亮度：列底=alphaBlend(accent 10%, surface) 两档通用（浅色=粉彩、暗色=深色调），卡片浅色**不透明白**（图中白卡浮于粉彩列）、暗色 80% 半透明（列色渗入卡面）；主色全部取 Notion 官方 muted 色系（蓝 #337EA9/绿 #448361 系/琥珀 #D9730D） | 4 张图共享的灵魂=列各有其色、底色安静、胶囊彩色——theme 提供底子、着色机制提供表情，一套机制吃下全部参考图；浅色图里卡片是不透明白（粉彩列衬托），暗色图里卡片半透明（暗色列渗入）——按亮度分支而非一刀切；Notion muted 色系保证多色胶囊共存不刺眼 |
| v1.12.18 | **新增"墨板 Notion Board"主题**（用户给 Notion 模板截图："Today 页面的 dashboard 是否可以参考图片增加一个主题"）：参考图=近黑背景 + 每列按语义着色的彩色玻璃列 + 半透明卡片透出列色 + 彩色胶囊标签。实现：① 新调色板 `notionBoard`（bg #0E0E0E/surface #151515/card #1C1C1C/border #2E2E2E/textPrimary #EDEDE9/primary=Notion 蓝 #2383E2）；② **看板专属配方**——`notionTint` 标志（theme==notionBoard）下 `_buildColumn` 每列背景=`alphaBlend(accent 10%, surface)`（状态/优先级/项目色随维度自动映射），TaskCard 填充恒 `cardColor 80%` 半透明透出列色（主题自带玻璃观感，优先于用户卡片设置）；③ 其余页面走常规暗色 surface。枚举插 nordNight 后，测试 10→11 + 签名锚点 | 图片的灵魂在"列各有其色"而非整体色板——accent 着色列让 Status/Project/Priority 三维度自然呈现不同列色（Project 维度=用户项目色）；卡片 80% 半透明让列色渗入卡面（图中 Work 蓝卡/Personal 紫卡的效果）；主题自带观感优先于玻璃设置，避免两套状态互相干扰；列头胶囊化未做（可后续按需加） |
| v1.12.17 | **主题精简：删除 11 款主题**（用户点名：默认靛蓝/清新淡绿/日落橙/薰衣草紫/青瓷/胭脂/薄荷/晴空/蜜桃/拿铁·薰衣草/拿铁·木槿紫）：枚举/双语标签/palette 映射/brightness 分支/AppColors 调色板五处同步删除，剩 **10 款**（浅：暖沙 warmSand、黛蓝 inkBlue；暗：dark、nordNight、Catppuccin Frappé×2/Macchiato×2/Mocha×2）；**默认主题 freshGreen（已删）→ inkBlue 黛蓝**（ThemeModeNotifier 初始值 + `AppTheme.light` getter）；AppColors **遗留色别名重映射**（lightX 六项+primary 三项从 indigoLight 值改锚 inkBlue 值——约 20 处 `isDark ? darkX : lightX` 硬编码调用点的浅色基准随之变化）；持久化按 name 字符串，被删主题的存量用户自动回退默认黛蓝；契约测试 21→10、签名锚点仅留 inkBlue、遗留别名测试锚点同步 | 沿用 v1.8.0"删除主题=删枚举值+未知 name 回退默认"的安全模式；默认选保留浅色黛蓝（中性 scholarly 蓝，接近原默认观感）；遗留别名是硬编码色值（非引用），重映射即可，全 UI 的 isDark 硬编码分支跟着换基准 |
| v1.12.16 | **浅色玻璃对比度修复 + 三页任务卡立体感**（用户反馈"①Today 浅色 dashboard 任务卡有暗淡模糊感；②③④ Timeline/Calendar/Activity 任务卡增加立体感"；注：上一轮同号尝试——半强度填充+TaskListCard 色条——被用户要求整体回退，本轮换思路且只做加法）：① **浅色玻璃列底改"着色玻璃"**——列底不再白洗（white 72%），改取画布深色调（canvasDeep + white 30%）着色，半透明白卡在着色列底上立即浮现对比，根除"所有层收敛到同一近白"的暗淡感；app 玻璃与卡片玻璃两分支共用此配方；② **卡片玻璃自动降透明度主题感知**——`setGlass(value, {lightTheme})`：浅色落 **85%**（55% 白在浅色上=暗淡泥灰）、深色维持 55%，Settings 开关传入亮度；③ **HoverLift 静置阴影**（black 5% blur7）——Timeline/Calendar/Activity 任务卡静置即有微浮立体感，hover 增强；测试断言 1→2→1 | 对比度来自"卡亮底彩"而非"卡更透"——不再动用户的透明度滑块（上轮半强度方案被回退的教训）；着色列底=v1.11.3 纸感配方的玻璃化转译（着色画布+白卡）；立体感只加静置阴影不做卡片结构改造（色条方案已被回退，不加回） |
| v1.12.15 | **浅色主题观感优化**（用户反馈"浅色主题都不美观，需要进行优化，页面中的各个模块可以不统一"——明确授权模块差异化）：① **环境画布常驻**——浅色非玻璃模式也有 whisper 版环境画布（border 20%/32% 混合 + 3.5–5% 静态光晕），玻璃模式保持鲜活版（55%/72% + 10–16% 漂移光晕）；深色非玻璃保持平面；② **模块差异化/纸面化**——侧边栏非玻璃浅色下从 3% 幽灵条改为 **card 色浮板+投影**，内容面板加柔和投影 + 90% 填充让画布微透（模块间隙有色），标题栏浅色非玻璃下透明（画布流到顶），边框 0.2→0.3；③ **页面级点缀**——Timeline 标题补主题竖条（对齐 Today）、Calendar 日面板改 card 色+投影、Activity 统计卡改 card 色+投影（经 cardTheme.color 取值，玻璃模式自动半透明） | 白底+描边的均质外观是"不美观"主因——所有模块一个模样=没有视觉层级；用户授权模块不统一后，外壳三层（画布→侧栏浮板→内容纸面）+页面内浮动模块建立层级；静态光晕是工程与体验的折中（无限动画会卡死 pumpAndSettle，且 5% 光晕的漂移不可感知，动效语言保留给玻璃）；深色零改动（已好看） |
| v1.12.14 | **新增 3 款清新浅色主题**（用户需求"设计3款清新浅色主题，可以使每个页面都从视觉上美观且有质感"）：**薄荷 mintFresh**（海盐青碧 accent #0F8F82 + 呼吸感薄荷画布 #E6F5F1）、**晴空 clearSky**（天蓝 accent #1E7FD0 + 微风蓝天画布 #E8F2FC）、**蜜桃 peachCream**（珊瑚陶土 accent #D2583F + 晨雾奶油画布 #FCF0E8）。质感设计规则（v1.12.11 教训内化）：① 每层带真实色相（bg/surface/card 阶梯明度差可见，纯白卡片在着色画布上浮起）；② border 有足够彩度喂玻璃画布加深（v1.12.11 机制自动受益）；③ 文字色带色相偏移（#113B34 类，非纯灰）。枚举插 dustyRose 后（浅色组内），测试 18→21 + 3 个签名锚点 | 与既有 8 浅色主题色相错位（薄荷≠freshGreen 草绿/celadon 灰玉，晴空≠inkBlue 灰蓝/indigoLight 靛蓝，蜜桃≠sunsetOrange 橙/warmSand 米/胭脂玫瑰）；白字对比遵循 Material-600 惯例；命名走 v1.7.0 单字诗意风（薄荷/晴空/蜜桃 对标 青瓷/黛蓝/胭脂）；设置页列表/亮度分组/GFM alert 色自动适配 |
| v1.12.13 | **Timeline/Calendar/Activity 任务卡悬停动效**（用户需求"当鼠标移动到任务上，没有动态效果"）：新共享组件 `HoverLift`（presentation/shared/hover_lift.dart）——MouseRegion(click 光标) + AnimatedContainer(180ms easeOutCubic)，悬停上浮 2px + 主题色阴影（accent 12% blur12 + black 6% blur8），builder 回调 hover 状态供条目高亮边框（accent 45%）；margin 参数移到外壳（内层 Container 的 margin 会让阴影框包含边距区域而错位）。三处接入：Timeline `_TimelineItem`（accent=statusColor，radius 12）、Calendar `_DayTaskItem`、Activity `_ActivityTaskItem`（accent=完成绿/优先级色，radius 10）——均与 Today TaskCard 的悬浮语言一致；+1 widget 测试（真实鼠标 gesture 验证 hover/无 hover/移出三态阴影） | 三个页面任务条目此前是纯静态 GestureDetector+Container，与 Today 卡片交互语言脱节；共享组件避免三处重复实现同款动效；margin 上移是阴影正确性的关键（AnimatedContainer 的 decoration 框=自身尺寸，含子级 margin 会把阴影画大） |
| v1.12.12 | **Today 画布恢复实色**（用户截图反馈"Today页面的dashboard的底色是毛玻璃，不够清晰"）：回退 v1.12.7 引入、v1.12.10 保留的画布半透明——半透明画布让外壳面板模糊后的环境光晕透进整个 dashboard，形成一片奶雾状毛玻璃底，内容反而不清晰。现在画布恒为实色（保留 v1.12.11 玻璃模式的加深色调，视觉上仍是"着色"而非"透明"）；玻璃效果集中在列底（半透明，叠在实色画布上磨砂清晰）与卡片；Interface Glass 滑块对 Today 的影响=列底透明度 | 半透明画布背后只有模糊光晕，任何透明度都是雾——"背景清晰"与"背景透光"在 Today 主内容区不可兼得，用户选清晰；列底+卡片仍是玻璃，界面玻璃滑块在 Today 仍实时可见（v1.12.7 的诉求保住大半） |
| v1.12.11 | **浅色主题玻璃修复**（用户双截图对比"浅色主题的预览效果差，深色模式的效果会相对比较好些"）：根因有二——① 浅色调色板全是近白色，半透明层叠加后全部收敛到白色，画布→列→卡明度阶梯消失（玻璃模式把 v1.11.3 修过的洗白问题带回来了）；② 玻璃卡片亮边在浅色下是白色，画在近白列底上完全隐形、卡片失去轮廓。修复：① 玻璃激活时（appGlass 或 boardStyle 任一开）浅色画布 border 混合 38%/52%→**50%/64%**，外壳环境画布 42%/58%→**55%/72%**（仅浅色分支，深色零改动）；② TaskCard 与 Settings 预览卡的玻璃亮边改为**主题感知**——深色保持白边、浅色用 `palette.outline`（0.65/hover 0.90） | 玻璃质感三要素（模糊+半透明+亮边）在浅色下全部失效的共性=背景不够深、白边无对比；向 border 混合保持主题色相（同 v1.11.3 手法）；outline 即 buildTheme 里 p.border 的 ColorScheme 映射，避免再引入 ThemePalette 依赖 |
| v1.12.10 | **两区完全独立 + 0–100% 全范围**（用户明确要求"Card Appearance 和 App Interface Glass 可以单独设置玻璃态效果以及透明度，范围从 0%–100%"）：① **删除 v1.12.8/9 的统一联动**——`effectiveBoardCardStyle` 函数整体移除，TaskCard/KPI/QuickAdd 回归只读 `boardCardStyleProvider`，Card Appearance 控件全部恢复常驻可用；② **职责划分**：Card Appearance=任务卡/KPI/快速添加栏（内容元素），App Interface Glass=标题栏/侧边栏/内容面板/**Today 画布与列底**（界面块，v1.12.7 语义保留）——列底 appGlass 开时跟随 `appGlass.opacity`，关而卡片玻璃开时按 `boardOpacity−0.2` 半透明（保 v1.12.6 卡片模糊可见性的前置条件）；③ **范围放宽**：两个 provider `minOpacity` 0.3/0.4→**0.0**，`buildTheme` 内 clamp(0.4,1)→clamp(0,1)，0%=完全透明；开启玻璃时的自动降透明度（卡 0.55/app 0.75）保留为默认值非下限；④ 设置区文案标注 "0% = fully see-through / Independent of the Interface Glass section" | 用户经历了"独立(效果割裂)→强制统一(卡片不可调)→联动可调"三轮后明确拍板要完全独立+全范围，尊重最终决定；0–100% 是用户显式要求（0% 时文字不可读由用户自担）；列底双保险逻辑保证单开任何一边玻璃都有效果 |
| v1.12.9 | **统一材质下卡片滑块恢复可调**（用户反馈"Today Board Cards 的玻璃态及透明度都无法调节了"——v1.12.8 把卡片控件禁用过猛）：统一模式（Interface Glass 开）下 Today Board Cards 的**透明度滑块与模糊滑块直接驱动全局共享状态**（`appGlassStyleProvider`，与 Interface Glass 区的滑块双向同步、改一处全 App 联动），滑块范围跟随被驱动的状态（app 40–100%）；玻璃开关仍禁用（统一材质恒为玻璃，总开关归 Interface Glass 区）；提示条文案改为 "Linked to Interface Glass — these sliders adjust the shared opacity & blur for the whole app" | v1.12.8 满足了一体性但牺牲了可调性，用户两个都要；正解=一个共享状态、两个控制面，而非禁用副控制面；透明度 0.3–0.4 区间在统一模式下无意义（面板承载正文），故跟随 app 范围 40% 起 |
| v1.12.8 | **玻璃材质统一**（用户反馈"透明度设置后，整个App不可以设置一体性"）：Interface Glass 开启时成为全 App 唯一玻璃来源——新纯函数 `effectiveBoardCardStyle(appGlass, boardStyle)`（app 玻璃开→返回 `BoardCardStyle(opacity: appGlass.opacity, glass: true, blur: appGlass.blur)`，关→原样返回 boardStyle），TaskCard/看板屏（画布、列底、KPI、QuickAdd）/Settings 预览全部经它取有效样式；列底=共用透明度 **-0.2**（clamp ≥ minOpacity）保持画布→列→卡的明度阶梯（0.75→0.55 恰为旧定值）；Settings→Today Board Cards 在统一模式下显示提示条"Following Interface Glass"并禁用三个独立控件（透明度滑块/玻璃开关/模糊滑块，徽章变灰） | 用户要"一体性"=一个旋钮管全 App，两套独立透明度必然拼贴感；卡片玻璃关、界面玻璃开时若卡片仍实色会破坏材质连续性，故统一模式强制卡片玻璃开；列底 -0.2 阶梯让层叠有主次而非平铺同值；独立控制保留在关掉 Interface Glass 后可用 |
| v1.12.7 | **Interface Glass 贯通 Today 页**（用户截图反馈"App界面的主题色各块区域透明度及玻璃态没有调节"）：根因=Today 页自绘不透明画布整个盖住外壳玻璃面板，Interface Glass 的开关/滑块在该页主区域零反馈；侧边栏填充也是写死的 10% 不跟随滑块。修复：① Today 画布在 app 玻璃开时按 `appGlass.opacity` 半透明（外壳环境画布+光晕透入整个主区域，模糊由外壳面板层免费提供）；② 列底色 app 玻璃开时也半透明（卡片玻璃关时主区域不再局部无反应；两者同开时卡片玻璃的 0.55 优先）；③ 侧边栏玻璃填充改为 `alphaBlend(primary 18%, surface)` 再乘 `appGlass.opacity`——透明度滑块直接控制侧边栏 | 用户心智模型=一个界面玻璃开关管所有主题色块，不关心内部两层系统的边界；Today 是主页面，界面玻璃在该页无反馈等于功能失效；外壳模糊已盖住面板下 everything，页内元素只需半透明即可获得磨砂观感 |
| v1.12.6 | 玻璃效果**可见性修复**（用户反馈"Today 页面/整个 App 界面玻璃态及透明度效果不佳"）：① **Today**——根因=卡片玻璃的模糊层后面是不透明列底色（white 72% 实色混合），画布光晕被列挡死、模糊糊的是一片平色；修复=玻璃开时列底色 `withOpacity(0.55)`，光晕透明度 ×1.8，KPI 卡与快速添加栏跟随卡片样式（半透明填充，KPI 走同款 ClipRRect+BackdropFilter 内侧填充配方，QuickAdd 用 GlassPanel 外包——无 transform 冲突）；② **全局**——环境画布加深（light border 30%/45%→42%/58%）、光晕 5–8%→10–16% 且加大，玻璃面板边框换**白色亮边**（light 55%/dark 16%，亮边是玻璃质感的关键线索），开启默认透明度 0.85→**0.75**；`_kpiFillGradient` 提为 getter 供 build 与 _wrapGlass 共用 | 玻璃观感=模糊(背后有内容)+半透明+亮边三要素，此前全局只满足其一；列底半透明是 Today 卡片玻璃可见的前置条件（模糊只能糊到直接背衬）；QuickAdd 无 transform 可外包 GlassPanel，KPI 有 hover 位移必须内包（裁剪随 transform 走，同 TaskCard） |
| v1.12.5 | **全局界面玻璃**（用户需求"整个App界面也支持玻璃态及透明度设置"）：① 新 provider `app_glass_provider`（`AppGlassStyle{glass,opacity,blur}`，键 `settings.appGlass/Opacity/Blur`，与卡片 provider 相同的串行化持久化）；② `AppTheme.buildTheme(mode,{glass,glassOpacity})`——玻璃开时 `colorScheme.surface`/`cardTheme.color`/appBar 背景按透明度变半透明，**scaffoldBackgroundColor 恒为不透明**（垫底防黑窗），普通 Card/面板经主题自动变毛玻璃无需逐个改；③ `AppShell` 转 ConsumerWidget——玻璃开时整窗铺环境画布（surface→bg 加深渐变 + 3 颗漂移光晕，Today 同配方），标题栏/侧边栏/内容面板用新共享组件 **GlassPanel**（ClipRRect+BackdropFilter，模糊在外壳层做一次，内部卡片靠半透明透出已模糊背景，避免几百个 BackdropFilter）；④ 侧边栏底色玻璃时 3%→10% 保证可读；⑤ Settings 新增 **Interface Glass** 区（开关+透明度 40%–100%+模糊 4–30，关闭时滑块禁用；开启时透明度自动降 85%——面板直接承载正文，比卡片的 55% 保守）；设置页本身即实时预览 | 模糊只在外壳三面板做一次是性能关键（BackdropFilter 全屏逐帧成本高）；主题层染色让全应用卡片零改动获得玻璃观感；Today 页画布不透明不受影响（其卡片有自己的玻璃设置），两层玻璃互不干扰 |
| v1.12.4 | 玻璃态从开关升级为**强度可调**（用户需求"可以调节玻璃态效果"）：`BoardCardStyle` 增加 `blur`（BackdropFilter sigma，**4–30 默认 14**），`TaskCard._wrapGlass` 与 Settings 预览卡共用同一来源；Settings 滑块在玻璃关闭时禁用（避免拖动无反馈），徽章同步变灰；持久化键 `settings.boardCardBlur` | 模糊强度是玻璃观感的主变量（透明度已有滑块）；4 的下限避免"零模糊玻璃"与关玻璃效果重复；blur 与 opacity/glass 同走一次 _persist 快照，无新增竞态面 |
| v1.12.3 | Settings 新增 **Today Board Cards** 区（用户需求：可设置 Today dashboard 任务卡片透明度/玻璃态）：① 新 provider `board_card_style_provider`（`BoardCardStyle{opacity,glass}`，shared_preferences 持久化 `settings.boardCardOpacity/Glass`，透明度范围 30%–100% 步进 5%）；② `TaskCard._buildCard` 应用——非玻璃=填充色直接乘透明度，玻璃=`ClipRRect`+`BackdropFilter(blur 14)` 包裹内容、半透明填充画在模糊层**内侧**、描边改白色亮边（hover 加强）；③ **开启玻璃时若透明度仍 100% 自动降到 55%**（不降则磨砂不可见），用户可再调；④ Settings 卡片带迷你画布实时预览（渐变+光晕+同配方玻璃卡）；⑤ `_persist` 串行化（链式 Future+调用时快照），避免同 tick 两次 set 的异步写交错让旧值覆盖新值 | 玻璃态本质=背景模糊+半透明填充+亮边三件套，填充画在 BackdropFilter 外侧会把模糊完全遮死；30% 下限防卡片文字在浅色画布上不可读；持久化写入竞态是单测实测发现的（glass 写成 false），同类老 Notifier（font/weight）单键写不受影响、不动 |
| v1.12.2 | note 预览可读性修复（用户截图反馈"太小且颜色太淡无法看清"）：字号 11→**12.5**、字重 w500、颜色 onSurface 50%→**78%**、行数 2→**3**、块底 outline 8%→10%、类型图标 11.5→13 | note 预览=卡片上最重要的"最新进展"信息，可读性优先于层级克制；描述仍保持 50% 灰形成主次 |
| v1.12.1 | 看板卡片新增**最近日志预览块**（用户需求：卡片可预览最近一次 notes 内容）：位置=描述之下、chips 之上；内容=executionLog 按 timestamp 取最新一条（`reduce` 求最新，不信任列表顺序），浅灰底圆角块 + 类型着色小图标（note=主题色便签/pass=绿勾/fail=红叉/blocked=橙 blocking）+ 内容最多 2 行省略。新增 `_latestEntry`/`_notePreview` | 引用式预览与描述视觉区分（描述=任务本身、note=最新进展）；图标色传达日志类型避免整块上色过度；Border(left)+borderRadius 组合在 Flutter 有非均匀边滤断言，故弃用左彩条改用着色图标 |
| v1.12.0 | 看板卡片**预览内容升级**（用户参考外部看板截图要求卡片展示预览内容）：① 描述预览 2 行→**3 行**（12px/height 1.45）；② 新增**底部统计行**（有内容才显示，Wrap 布局）：📎 附件数（=executionLog 各条 attachments 总和）、💬 日志条数（executionLog.length，类比截图的评论数）、**子任务进度环**（12px CircularProgressIndicator + 百分比，<100% 主题色、=100% 绿色，取代原 n/m chip）；③ 优先级 P0-P3 徽章**常显**（原先是"无其他 meta 就整行隐藏"）；删除被孤立的 `_hasMetaChips`。卡片结构=标题→描述→chips（优先级/截止/项目/标签）→统计行 | 映射：截图的 💬评论→TaskFlow 的执行日志、📎附件→日志内附件、◔进度环→子任务完成度；统计行条件显示避免空卡噪音；环形进度用 CircularProgressIndicator(determininate) 零自绘 |
| v1.11.3 | Today 看板浅色主题二次修（用户双截图对比：深色好看、浅色仍难看）：根因=浅色主题 `bg` 只比白深 3~5%（freshGreen #F0FAF4/celadon #EEF4F1），v1.11.1 的「bg 画布→白 62% 玻璃列→纯白卡」三层几乎无明度差。修复（**全部走 isDark 分支，深色零改动**）：① 浅色画布向 `palette.border` 加深——canvas=alphaBlend(border 38%, bg)、底部渐变到 52%（保持主题色相，如 freshGreen≈#DFF0E7）；② 玻璃列提实=white 72% 叠 canvas，列顶洗底 4%→6%（顶部 35%）；③ 浅色阴影加强：列 black 5%·blur10、卡 7%·blur9、KPI 7%·blur9，KPI 角部洗底 7%→9%，空列虚线框 border 0.45→0.6 | 三层阶梯必须有真实明度差（深色天然成立：#1E1E2E→#2A2A3C→#45475A）；向 border 混合而非向黑混合可保主题色相；全部调色走 alphaBlend 实色避免透明度叠加发灰 |
| v1.11.2 | 修 Today 看板**最右列被裁切**（用户截图：Blocked 列右侧被推出可视区）：根因=`_buildBoard` 的 LayoutBuilder 在左右 28px Padding **外侧**取 `maxWidth`，列宽均分与 ConstrainedBox minWidth 都按含边距全宽算，内容恒比可视区宽 56px（水平可滚但看不出该滚）。修复=LayoutBuilder 移入 Padding 内侧，`available` 为扣边距后的真实宽度再均分。同类布局校验：KPI 行/工具栏的 LayoutBuilder 均已在 Padding 内侧，无同款问题 | Padding 会收缩子级约束但不会改 LayoutBuilder 已取到的值；「取宽用的 LayoutBuilder 必须与消费宽度的布局同层或更内层」 |
| v1.11.1 | Today 看板浅色主题修复（用户截图反馈黛蓝等浅色主题下"不美观没质感"）：根因=浅色主题 `surface`/`card`/`bg` 三色差过小（如 inkBlue #FAFBFD/#F2F6FA/#EFF3F8），再叠 v1.11.0 的大面积元素——页头 6% 主色渐变带、整列 5% 强调色洗底、KPI surface 渐变——全部糊在一起。修复=**「纸感」配方**：① 页面画布统一用 `palette.bg`（灰蓝底），② 浅色主题卡片（任务卡/KPI/快速添加栏）一律**纯白** `Colors.white`（深色仍用 palette.card），③ 列改「玻璃」=浅色 white 62% / 深色 card 40% 叠加 bg 的实色混合，④ **删页头渐变带**（改平铺标题）、整列洗底缩到顶部 30%·4%、列/卡边框加深（outline 0.5~0.7）+ 阴影加强（black 5%），彩色只留小元素（左色条/图标章/徽章/发丝线/hover）。KanbanColumn 增加 backgroundColor 参数（屏幕层按亮度解析），kanban_column 不再依赖 themeModeProvider | 层次感=中性面保持中性、彩色只做小面积点缀；白卡+边框+阴影在灰蓝画布上才有 translate_tool Paper 主题的「浮起」感；全 18 主题按亮度分支自动生效 |
| v1.11.0 | Today 看板两轮迭代（用户需求：更美观有质感 + Dashboard 可按 Project/Status 等方式展示）：① **维度切换**——新增 `BoardDimension`（Status/Project/Priority）+ `boardDimensionProvider`，工具栏（快速筛选 pills 居左 + 维度分段控件居右，窄窗 <760px 纵向堆叠防溢出）切换，`KanbanColumnData` 泛化为 key+tasks（status=状态名/priority=索引/project=项目名，''=No Project）；**拖拽跨列=改对应属性**（状态→updateStatus、优先级/项目→updateTask），列头"+"新建同样按维度继承属性，切维度淡入过渡（AnimatedSwitcher+Positioned.fill 布局器）；Project 列按字母序（No Project 殿后）、空集也保底一列，优先级列固定 P0-P3 恒显；② **质感升级**——页面级环境层：整页 surface→primary 2.5% 纵向渐变 + 3 颗 14s 往返漂移的径向光晕（primary/secondary/success，4-7% 透明度，IgnorePointer）；KPI 卡：accent 向右下 7% 渐变底、右上 accent 图标章、左色条改渐变、hover 上浮+发光；看板列：圆角 18、列内 accent 5%→0 纵向渐变洗底、列头图标块 26px 渐变底、列表加 Scrollbar；卡片左色条改纵向渐变。10 项看板契约测试扩到 13 项（新增 priority/project 分桶+空集保底） | "质感"=低饱和环境层+微渐变+hover 微交互，不动整体视觉语言；Tag 维度刻意不做（任务可属多标签→同卡多列+拖拽语义歧义），如用户后续要再扩展 |
| v1.10.0 | **Today 页看板化改版**（对标 translate_tool 的 todolist 看板）：① `TaskBoardScreen` 重写为 **4 张 KPI 统计卡**（Today's Progress 带渐变进度条/To Do+逾期数/In Progress+高优先数/Done+完成率，KPI 统计口径=全量任务不受筛选影响）+ **固定四列看板**（To Do/In Progress/Done/Blocked，列头=状态色图标块+计数徽章+"+"列内快速添加，列顶状态色发丝线，空列呼吸虚线框）；② 卡片重写（task_card_widget.dart）：左侧 3px 优先级色条（完成变绿）、标题+hover 操作（完成切换/编辑/删除）、两行截断描述、meta 胶囊链（截止日期逾期红/今日主题色、优先级、子任务 n/m、项目/标签用户色）；③ **拖拽跨列改状态**（整列是 DragTarget，卡片 DragTarget 转子任务优先级更高、两者共存），Archived 归入 Done 列（全应用 completed‖archived 约定）；④ 顶栏快捷筛选 pills（All/Due Today/High Priority，StateProvider 本地态）；⑤ 数据层：`task_providers.dart` 新增 `buildKanbanColumns`/`sortKanbanTasks`/`applyBoardQuickFilter`/`buildKanbanBoardData` 纯函数 + `kanbanBoardProvider`（10 项契约测试 kanban_board_test.dart）；⑥ `createTask`/`buildNewTask` 加可选 `status` 参数（默认 planned，既有调用零改动）；⑦ 删除被孤立的 Group-by 体系（TaskGroupMode 枚举/taskGroupModeProvider/groupedTasksByModeProvider），Today 页不再用 WheelForward（其他页保留）；列内排序=截止日期升序（无日期沉底）→优先级→创建时间降序 | 用户需求"Today 页做成类似 translate_tool 的任务清单页"；statusColor 仍是列色唯一事实源；保留快速添加栏与外部筛选横幅（Activity 页联动） |
| v1.9.3 | 报告总结优化三件套：① 执行摘要 In Progress=每任务一行（加粗标题+" — "+一句话总结，删缩进要点）；② 进度明细近因聚焦 10 天→**7 天（近一周）**，超一周日志压成"早期背景："一句历史总结，详情条目=任务详细描述；③ 下期计划**只含未完成任务**（计划/进行/阻塞逾期）且**每任务一行禁止分解**（删"可分解为多个行动行"指令）。改动面：`formatTaskData` recentCut 10→7 天+标签、中英 AI 提示词（输出模板/分节规则/质量自检）、回退模板 toMarkdown/toHtml 的 In Progress 小节；契约测试同步（253→254） | 用户三需求（In Progress 一句话总结；详细描述+近一周重点+超一周一句话历史；计划只针对未完成任务、不细化）。整周报告期（start=end−7d）下"近期但期外"分档为空集，契约测试改用 07-15→07-20 短周期构造该分档 |
| v1.9.2 | Timeline `_filterTasks` 排序升序→**降序**（最新在最上、久远在底下）；`isLast` 竖线逻辑不动（isLast=最底最旧一条，链条自上而下仍连贯） | 用户读时间线的习惯是自上而下从最近看起 |
| v1.9.1 | Timeline `_TimelineItem` 左侧时间列 52px 单行 HH:mm → **96px 两行堆叠（yyyy-MM-dd 上、HH:mm 下）**，样式沿用 labelSmall+lightTextSecondary | 范围模式下多天任务同列只有时刻无日期，无法辨认归属日；96px 按 labelSmall 11px×140% 缩放 ×10 字符留足余量 |
| v1.9.0 | 用户两需求：①删除"系统默认"预设，**Inter×MiSans 成为应用默认字体**（defaultFont 改指 interMisans；旧 'system' 持久化 id 经未知 id 路径安全迁移到默认；预设仅剩 3 配对；离线首启 Inter 下载失败由 MiSans→HarmonyOS 回退链兜底）；②Timeline `_TimelineItem` 任务标题补 completed/archived 画线+变淡（此前完全无画线，与 Today TaskCard 不一致；状态点/徽标保持真实状态色不动） | 用户明确"Inter×MiSans 设为系统默认"；画线对齐以 Today 看板为基准，状态徽标保留信息量 |
| v1.8.0 | 用户实测 v1.7.0 后四需求：①删三深色主题（espresso/deepSea/aubergine），保留青瓷/黛蓝/胭脂（18 主题；持久化按 name，已选被删主题者回退 freshGreen）；②字体预设裁至 系统默认+3 配对（interMisans/jakartaNoto/lexendNoto），删除 notoSansSC/poppins/两 Manrope 配对/serif/文楷/plex/outfit 及整个 systemFonts 列表（AppFonts.all=presets；内容/输入字体下拉随之只剩 3 配对家族+Follow global+custom），app.dart 两 switch 同步清孤儿分支（_ensureCjkFontLoaded 只留 Noto Sans SC、_googleFontTextTheme 只留三拉丁）；③修复 Settings→AI 三输入框不自动加载——根因是 AiConfigNotifier 懒创建+_restore() 异步，而 _AiConfigCard._ensureLoaded 首帧即锁存 `_loaded`，把空默认值永久写进输入框（且后续手输触发 autosave 会把存量配置覆盖成空）；修复=Notifier 加 `restored` 标志（赋值在 state 置换前），_ensureLoaded 在 restored 前直接 return，等 watch 重建后自然装载；④统一 Archived 渲染——heatmap `_ActivityTaskItem` 与 calendar `_DayTaskItem`/`_DuePill` 三处 `isCompleted` 只判 completed 漏 archived，补齐后 Archived 与 Today 看板 TaskCard 同为绿点+画线（README Phase 6 约定）；契约测试同步（主题 18/字体裁剪后共 253） | "系统默认"是离线优先兜底（内置 Manrope×MiSans 栈）且是被删 id 的回退着陆点，故保留；修复竞态时 `restored=true` 必须在 `state=` 之前赋值，否则同步监听仍见旧值 |
| v1.4.73-77 | 移除全局 SelectionArea，内容区统一 SelectableMarkdownBody | SDK bug：右键时 `_handleRightClickDown` 命中测试失败清空选区 |
| v1.4.78-80 | 拖拽合并/提取用 `SubStepOrigin` 快照（Task 级列表） | SubStep 嵌入对象字段冻结，不能加字段 |
| v1.4.83 | 附件存相对文件名 + 三级解析 | 跨设备路径不同，绝对路径失效 |
| v1.4.84-87 | Drive 同步：附件镜像 + 占位文件不预过滤 + `attrib +P` 钉住 + 路径自愈合 | Drive 云端占位文件 `existsSync()` 为 false，预过滤会永久跳过；盘符重启变化 |
| v1.4.88 | Progress Details 由 `<br>` 表格改为清单版式；AI 喂全部日志 | 应用内 MarkdownBody 不渲染 `<br>`；深度理解需要全量历史 |
| v1.4.90-91 | 编辑对话框 → 输入区内联编辑 + 显式 Update 按钮 | 用户要同一编辑环境；纯快捷键入口不可发现 |
| v1.4.96 | Catppuccin 四风味八主题 | 用户指定色彩体系，官方色值 + WCAG 映射 |
| v1.4.98 | Latte 表面层级反转修正（card>surface>bg）；删 4 主题 | 官方 base/mantle 映射在 light 下发灰；用户精简主题 |
| v1.5.0 | 扩展 Markdown：脚注/上下标/高亮样式修复；**Mermaid 与 LaTeX 明确不做** | 填充 GFM 空白；用户拍板剔除重依赖能力（无 WebView 前提下 Mermaid 无高性价比路线） |
| v1.5.0 | 自定义 rich 语法注册在 StrikethroughSyntax 之前 | 包的删除线贪婪吞单 `~`，下标语法在其后永远不匹配 |
| v1.5.1 | 块间距按上下文（标题紧贴/段-列表无空行） | 统一 `\n\n` 分隔导致"多余空行"，与标准 Markdown 预览观感不符 |
| v1.5.2 | 字体升级 Manrope（可变）× MiSans；默认字体改内置栈；双 Provider 补中文回退 | 质感+体积（42→35.8MB）；离线首启不再闪系统字体；修复内容/输入链中文落系统字体的缺口 |
| v1.5.3 | GFM 表格/任务清单/Alerts/LaTeX 两链补齐；alerts 在可选链降级为着色标签+槽线文本、公式降级为 WidgetSpan（不参与选区/复制丢失）；任务清单只读 ☐/☑ 无点击交互；仅禁 Mermaid，LaTeX 解禁（用户重提） | 表格字面 `\|` 根因是硬换行硬化破坏行结构；checkbox 需 hoist 才不被丢；builder 拿不到子节点故 alerts 靠 data-source 重渲染；flutter_math_fork 0.7.4 纯 Dart 无 WebView 路线验证可行 |
| v1.5.4 | 可选链表格弃文本网格改 **WidgetSpan 嵌入真实 Table**（用户实机否决 ASCII 网格后拍板，给过两选项）；任务清单 checkbox 两链改 Material 图标（`Icons.check_box(_outline_blank)`，替代细弱字形）；alerts 容器加类型图标+全周发丝描边+左色条 ClipRRect，可选链槽线 `│ `→`▎ ` | 文本网格对齐在混排下不可靠（踩坑 8.24）；表格文字随之退出选区/复制流（与公式同级的已接受降级，Copy as Markdown 不受影响） |
| v1.5.5 | alerts 按用户提供的 GitHub 参考截图重构：**纯淡色圆角卡（无左色条无边框）+ 首字母大写标签**（"Important" 非 "IMPORTANT"）+ GitHub 系图标（tip=火焰/important=report 八角标/warning=三角/caution=八角叉）；LaTeX 公式 fontSize 显式乘 `MediaQuery.textScalerOf`（flutter_math_fork 自绘不响应全局 80–140% 缩放，>100% 时公式相对正文变小） | 用户截图对标 GitHub 2023 改版样式；公式缩放失配是"排版不美观"的根因 |
| v1.5.6 | 报告生成四项打磨（用户需求）：① 状态仪表盘 Headline 格改 **`<br>` 分隔的至多 3 条任务要点列表**（AI 提示词 + toMarkdown/toHtml 确定性渲染同步，应用内 BrSyntax/导出 HTML 原生渲染换行）；② 执行摘要要点行**去掉 sub-step 比例**（只留加粗标题）；③ 进度明细 **10 天近因聚焦**——formatTaskData 以报告期结束日为基准，近 10 天日志完整投喂、更早的标注 "(older than 10 days — context only)"（12000 字符上限保留），提示词要求旧日志压缩为至多一句"早期背景："置于任务要点末尾（计入 5 条上限）；④ 导出 HTML 本就由 Markdown 源渲染（markdownToStyledHtml/EmailHtml），MD 改动自动带动 HTML 一致 | 用户要求报告更聚焦近期、版式更整洁；Headline 单行信息量不足 |
| v1.5.7 | 新增 **AI Prompts 页面**（侧边栏 AI Parse 下方，`/prompts`）：输入粗糙需求 → `AiService.generatePrompt`（system=用户提供的提示词工程专家 playbook 常量 `promptEngineerSystemPrompt`，user=`# 用户需求\n{输入}`）→ AppMarkdownBody 渲染 📋提示词/⚠假设/💡使用建议 三段输出 + **Copy prompt**（`extractPromptBody` 抓首个代码块）/Copy all；不落盘纯草稿页；未配置 AI 时提示去 Settings | 用户给定完整 playbook 文本原样入库；顺带修复 Generate 按钮不随输入启用（TextField 不触发 rebuild，接 AnimatedBuilder）与侧边栏 "AI Prompts" 标签 7px 溢出（8.7 同款，Flexible+ellipsis） |
| v1.5.8 | AI Prompts 四项打磨（用户需求）：① 输入框**拖拽调高**（grip 柄 120–420px，Work Log/AI Parse 同款）；② 输入改 **MarkdownEditorField**（Write/Preview 切换，与其他输入区工具链一致）；③ 字体联动 Settings——输入走 `applyInputTypography`（Settings→Fonts 输入区 family/size），预览与输出走 `applyContentTypography`（内容区设置）；④ 质感——输出卡片 surface 底+圆角 12+RESULT 头条、代码块淡底面板+边框（提示词正文即复制目标的视觉强化）、预览与输出共用同一 styleSheet（WYSIWYG） | 输入框是页面主体，可调大小+markdown 支持是工具页刚需；字体双链路复用既有 Provider 体系不另起炉灶（禁忌 9.11 回退链由 apply*Typography 内建） |
| v1.5.9 | 五项优化（用户需求）：① AI Prompts 输入/结果**跨页面保持**——`aiPromptsInputProvider`/`aiPromptsResultProvider` 会话级 StateProvider（ShellRoute 每次导航销毁页面 widget，草稿必须放 provider）；② 输入区加 **MarkdownToolbar**（标题/粗斜体/清单/缩进等与全应用一致）；③ 报告**移除 Overall 总结行**（MD/HTML/双语提示词/`_overallRag`/样式全链清除）；④ 执行摘要**结构化**——`_firstSummary`→`_summaryLines`，AI 摘要每行独立缩进要点（MD/HTML/双语提示词同步）；⑤ 导出 HTML **`_escapeTildesForHtml`**——markdown 包删除线语法连单 `~` 都匹配，"Vout ~ 5V … temp ~ stable" 两波浪号间全成删除线；报告不用删除线、`~` 即约等号，全量转 `&#126;`（StyledHtml+EmailHtml 两路径） | ShellRoute 生命周期决定状态必须外置；单波浪号误判删除线是 markdown 包 StrikethroughSyntax 的 `~~?` 贪婪匹配所致 |
| v1.5.10 | 全页面输入框 Tab 缩进审计收口：全应用 Markdown 输入区统一 `markdownIndentFocusNode`（Tab 缩进当前行/选区、Shift+Tab 反缩进）——Work Log（`_onInputKey` 自处理）、执行日志（内联 onKeyEvent）、AI Parse/Reports/建任务/编辑任务对话框、MarkdownEditorField 默认节点本已支持；唯一缺口 **AI Prompts 编辑器用裸 `FocusNode`**（Tab 移焦点不缩进）→ 换 `markdownIndentFocusNode(_inputController)`。单行字段（搜索/配置项）保持 Tab=焦点导航不改动 | 用户要求"所有页面输入框支持 Tab 缩进"；审计先行，只修真缺口（外科手术式改动） |
| v1.7.0 | 六新主题三浅（celadon 青瓷/inkBlue 黛蓝/dustyRose 胭脂）三深（espresso 深咖啡/deepSea 深海蓝/aubergine 墨紫），低饱和纸感/器物质感路线，每套 10 字段齐备、枚举按组插入；三新字体配对 interMisans=Inter×MiSans、jakartaNoto=Plus Jakarta Sans×思源黑体、lexendNoto=Lexend×思源黑体（google_fonts 在线下载零包体；`pairInterMiSans` id 已被 Manrope 占用故新 id 另起名）；顺带修复 v1.6.0 pairPlexNoto/pairOutfitMiSans 拉丁半 `_googleFontTextTheme` 分支缺失（预设存在但字体从不下车，补 IBM Plex Sans/Outfit 两 case）；新增 theme_palette_test（21 枚举/唯一 name/双语标签/亮度分组/bg 最暗层阶梯/signature 色锁定）+ 字体契约（新预设字段 + GoogleFonts.asMap 验证所有预设家族真实可解析）；255 测试全过（+13）、双推 `29bedd0`、包体 35.7MB | 用户要"精美有质感的主题 + 中英文都美观的字体"；层级断言只约束 bg 最暗层、不约束 card vs surface——Latte 教训（禁忌 6）：浅色下 card 可高于 surface |
| v1.6.5 | Custom 日期范围单弹窗（用户需求）：v1.6.4 两步两次弹窗被反馈“希望一页选完”→ 新建自定义 `_RangePickerDialog`：**复用 Daily/Weekly 同款 `CalendarDatePicker` 日历网格**（观感已被用户认可），交互=点一天→开始日、再点→结束日（早于开始日则原地重开；两端已齐再点则全新重选；同日点两次=单日范围），OK 在两端齐后启用，Cancel 返回 null；头部主色淡染+范围实时读出头条+Start/End 状态 chip（短日期格式 formatShortDate，标题 FittedBox 自适应、chips 用 Wrap 防窄布局溢出——踩坑：测试环境 Ahem 字体每字 1em 宽，Row 硬排会溢出，改用 Wrap 后两全）；API 签名不变三处零改动；文案全 MaterialLocalizations；5 项契约测试（单弹窗主流程/早于开始日重开/同日双击单日/Cancel/预填直接 OK，共 242） | 自绘选择器时横向状态条用 Wrap 不用 Row；日期格式选短格式（formatShortDate）不选带星期的 medium 格式 |
| v1.6.4 | Custom 日期范围弹窗最终方案（用户需求）：v1.6.1–1.6.3 三连调 Material `showDateRangePicker` 的尺寸/样式后用户仍觉得“难看”→ **改用 Reports Daily/Weekly 同款 `showDatePicker` 单日期弹窗**（紧凑对话框、自动继承应用 ColorScheme、观感已被用户认可）：`showAppDateRangePicker` 重写为**两步流**——① 先选开始日期（helpText=Start Date，默认上次范围起点或今天-7 天）；② 再选结束日期（firstDate=已选开始日，只能选不早于开始；默认上次范围终点或开始日）；任一步 Cancel 则整体返回 null。API 签名不变（Timeline/Calendar/Reports 三处调用零改动）；文案全走 MaterialLocalizations；测试重写为 4 项契约（两步流产物、首步取消、末步取消、结束日下限）。注意 M3 单日期弹窗选日后需按 OK 确认才关闭（测试要点选日→点 OK） | 用户对控件观感不满意且多轮微调无效时，停止调样式，改用用户已经认可的现成控件 |
| v1.6.3 | 日期范围选择器定稿（用户按规格要求）：① 倍率 1.5× 降至 **1.1×**——布局取 SDK 竖版网格宽度上限 **480×500**（零留白，不加大 MediaQuery），FittedBox 1.1× → 视觉 **528×550**（宽 500–560 达标、6 行网格月 484px 完整可见不滚动）；② “布局≈视觉+≤1.1×”评估**可行并直接采用**——1.1× 下描边/字重近乎原生（今天圈 1.4→1.54px），不再保留 1.5×；③ rangePicker*/普通槽位全部对齐共享卡片配方（背景 `cardTheme.color`=palette.card、边框 outline 80%、圆角 18、阴影 primary 10% 暗色无，15 主题自动生效）；④ 按钮统一（取消=描边、确定=主题色填充、等高圆角）+ 文案去硬编码全走 MaterialLocalizations（当前英文与全应用 UI 一致，locale 自动跟随）；⑤ 契约测试迁移为 480×500 布局 + 528×550 视觉双断言，并新增 3 档字号（100/125/140%）× 2 档 DPR（1.0/2.0）共 6 组合无溢出错位回归 | 三连迭代教训：倍率 >1.2 显粗糙、<500 宽显小，最终“网格上限布局+低倍率”是甜点位；Material 文案一律 localizations 取值 |
| v1.6.2 | 日期范围选择器尺寸回执（用户需求）：v1.6.1 的 420×520 太小 → **FittedBox 1.5× 等比放大**——picker 以 440×460 布局（SDK 月份网格宽上限 384/480 决定布局尺寸上限），FittedBox.contain 等比放大至视觉 **660×690**（长宽比完全匹配故内部零留白），日历格子/字体/表头全部同比放大，点击与拖拽滚动命中由 RenderFittedBox 正确变换；契约测试从 420×520 迁移为双尺寸断言（440×460 布局 + 660×690 视觉） | 想要大弹窗又无留白：直接加大 MediaQuery 会撞 SDK 宽度上限产生内部留白，等比放大是唯一路线 |
| v1.6.1 | 五项优化（用户需求）：① **AI Parse 总结会话级**——parse/summarize 移入 `aiParseSessionNotifier`（ProviderContainer 应用级生命周期，不随 ShellRoute 切页销毁）：切页不打断 AI 调用、结果落 provider 状态回页即见；总结只在**新结果落地**时被替换（进行中/失败均保留旧总结），输入/附件/任务结果一并跨页保持；② 总结新增 **Copy Markdown**（原样复制源码）+ **Save .md / Save .html**（复用 Work Log 的 `markdownToHtmlExport`/`wrapHtmlExportPage` 管线，saveFile 对话框，默认名 `ai-summary-日期`）；③ **Tab 语义反转**：光标处插入两个空格（仅光标后内容右移），多行选区仍整块缩进、Shift+Tab 仍反缩进（用户明确“不是整行缩进”，v1.5.10 整行判定推翻，回归测试按新契约改断言）；④ Timeline/Calendar 默认范围近一周改**近 30 天**（`defaultWeekRange`→`defaultMonthRange`）；⑤ 日期范围选择器**根因修复**——Material `_DateRangePickerDialog` 日历模式取 `MediaQuery.sizeOf` 全屏 + insetPadding 零（踩坑 8.26），桌面端日历浮在全屏弹层中间两侧巨幅留白；builder 内覆写紧凑 `MediaQuery(size: 420×520)` + 补齐 `rangePicker*` 主题槽位（此前 header/背景等普通字段对日历模式不生效） | 会话级状态必须放 ProviderContainer 而非页面 widget；Tab 行为用户两轮反馈最终拍板光标插入；`rangePicker*` 与普通槽位是两套字段 |
| v1.6.0 | 七项需求大轮:1 **新增 2 主题**--Nord Night(官方 Nord 调色板,极夜蓝/霜蓝主色)+ Warm Sand(暖纸底/焦糖主色),共 15 主题(枚举追加式,按 name 持久化安全);**新增 2 字体配对预设**(IBM Plex Sans×思源黑体、Outfit×MiSans,google_fonts 在线下载零包体);2 **AI 配置自动保存**--三个输入框接防抖 600ms 静默 save(`_loaded` 门闩防止恢复期覆盖),Save 按钮保留;34 Timeline/Calendar **默认近一周**(`defaultWeekRange()`,rangeMode 初始即开);5 **`showAppDateRangePicker`** 共享选择器(圆角 18 浮窗/主题色表头/主色选中/hover 高亮,DatePickerThemeData 全量定制),Timeline/Calendar/Reports Custom 三处接入;6 **AI Parse 大升级**--解析提示词输入框(可选)+ 附件按钮(`ContentExtractor`:txt/md/csv/log/json/eml 直读、html 剥标签、docx/xlsx/pptx 经 archive+xml 解包 OOXML、PDF 经 pdf_document/pdf_graphics 纯 Dart 抽取,150MB 上限),有提示词或附件时走 **analyzeContent** 总结模式(markdown 结果+Copy),无则保持任务抽取流;邮件检测(.eml 或 From:/Subject:/发件人特征)自动切 **emailThreadSystemPrompt**(SKILL.md 精编:正序时间线/数字保真/数值漂移标注/已拍板vs未拍板/四段式+三方 To Do);7 Tab 缩进"只缩光标后"报告--**代码本就是整行缩进**(行首插入),6 项回归测试锁定(行首/居中/行尾/第二行/多行选区/反缩进) | PDF 路线选 pdf_document+pdf_graphics(纯 Dart verified,拒 pdf_text_extraction 的原生 DLL 方案);OOXML=ZIP+XML 用 archive 解包不引 Office SDK;PowerShell 批量改文件曾破坏三文件换行(git checkout 恢复后改用 Edit 工具--**教训:禁用 Set-Content 批量改源码**) |

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
| 8.14 | 下标 `~x~` 语法不生效，'2' 被渲染成删除线 | markdown 包 `StrikethroughSyntax` 贪婪匹配单 `~` | 自定义 rich 语法移到内联语法列表最前（先于 StrikethroughSyntax） | 新增内联语法时检查与包内置语法的匹配优先级，用契约测试守护 |
| 8.15 | 展示区"多余空行" | SelectableMarkdownBody 顶层块间统一插 `\n\n` | 按上下文分隔：标题后/段-列表衔接用单 `\n`（v1.5.1） | 扁平化渲染器的空白策略必须有契约测试（selectable_spacing_test） |
| 8.16 | 小米 CDN 字体包下载报 "Authentication failed"/TLS 错 | CDN 临时抖动 | 延迟 30 秒重试；Invoke-WebRequest + Start-BitsTransfer 双通道 | 外部 CDN 大文件下载必有重试+备用通道，失败不阻塞时先继续其他步骤 |
| 8.17 | StateNotifier 持久化恢复测试失败（mock 值正确但 state 未变） | 测试用错持久化键名（字体是 `settings.fontId` 不是 `settings.themeMode`）；且 `Duration.zero` 不足以排空异步微任务 | 核对真实键名；等待用 `Future.delayed(50ms)` | 测持久化恢复前先读源码确认 _storageKey；StateNotifier 异步恢复测试统一 50ms |
| 8.18 | 内容/输入字体选纯英文后中文变系统字体 | `applyContentTypography`/`applyInputTypography` 只设 `fontFamily` 无回退链 | v1.5.2 强制同步写 `FontStack.fallback` | 见禁忌 9.11；font_upgrade_test 守护 |
| 8.19 | GFM 管道表格被渲染成字面 `\|` 文本行 | 硬换行硬化给表格行加了尾部两空格，TableSyntax 定界行匹配失败；AI 多行单元格也破坏行结构 | `prepare` 管线：多行行归一（`<br>` 连接）+ 硬化豁免 `\|` 开头行 | 任何“逐行改写”的预处理必须给结构性行（表格/`$$`/alert 起始）留豁免，并有单测固化 |
| 8.20 | 任务清单复选框在 AppMarkdownBody 里消失（只剩 •） | markdown 包把 `<input>` 插进 `li` 的首个 `p` 内部，flutter_markdown 只认 `li.children[0]` 位置的 checkbox | 自定义语法 `_hoistTree` 把 `<input>` 提升到 `li` 首子节点 + `checkboxBuilder` 渲染 ☐/☑ | 用包自带 checkbox 语法时验证 AST 中 checkbox 的位置是否符合渲染器预期（写契约测试） |
| 8.21 | `<br>` 在 AppMarkdownBody 渲染为字面文本（历史已知局限，v1.5.3 解决） | 无 InlineHtmlSyntax（故意，防吞 `<font>`） | 窄义 `BrSyntax`（只匹配 `<br\s*/?>`）→ flutter_markdown 0.7.7 原生支持 `br` 元素渲染为 `\n` | 需单个 HTML 标签能力时写窄义 InlineSyntax，不引 InlineHtmlSyntax（禁忌 9.3） |
| 8.22 | flutter_markdown 的自定义块容器（alerts）内容丢失 | builder 返回 widget 时默认子节点被丢弃，且 builder 拿不到已构建子节点 | 语法层把去 `>` 后的源文本存进 `data-source` 属性，builder 内嵌套 AppMarkdownBody 重渲染 | 给 flutter_markdown 写块容器类 builder 时，内容必须自带重建源，别指望访问子节点 |
| 8.23 | 任务清单 ☐ 出现两次（bullet + 内联） | 提升到 `li.children[0]` 的 `<input>` 仍会被当内联节点访问，若注册 `'input'` builder 会与 `checkboxBuilder` 双重渲染 | 不注册 `'input'` builder（未知内联元素天然不输出） | 给 flutter_markdown 注册 builder 前先确认该元素是否已在别的路径（如列表项检查）被消费 |
| 8.24 | 可选链表格 ASCII 文本网格中文列错位、观感如字符画（用户实机否决） | 等宽拉丁字体的 advance 与 CJK 字形 advance 不是精确 2:1（MiSans ≈1em vs Courier ≈0.6em），TextSpan 纯文本列对齐在混排下数学上就不可靠 | v1.5.4 弃文本网格，WidgetSpan 嵌真实 Table（IntrinsicColumnWidth 天然对齐） | 跨字体"按显示宽度补空格对齐"的方案在 CJK 混排下不可行，直接用真组件渲染 |
| 8.26 | Material 日期范围选择器在桌面端的观感问题（全屏留白→反复调尺寸→最终弃用） | ① 日历模式 `size = MediaQuery.sizeOf`（整窗）+ `insetPadding = EdgeInsets.zero`，月份网格宽上限 384/480 居中 → 全屏弹层+巨幅侧留白；② 且日历模式只读 `rangePicker*` 主题槽位，普通 `headerBackgroundColor` 等对它不生效 | v1.6.1–1.6.3 三连调尺寸（420×520→1.5× 放大 660×690→480×500×1.1 视觉 528×550）均未能让用户满意；**v1.6.4 最终方案：弃用 `showDateRangePicker`**，改用 Reports Daily/Weekly 同款 `showDatePicker` 单日期弹窗（自动继承应用 ColorScheme），两步流：先选开始日期（helpText=Start Date）、再选结束日期（firstDate=开始日期，只能选不早于开始），任一步取消则整体返回 null；API 签名不变三处调用零改动 | 用 Material 复合弹层前先读 SDK 源码的尺寸/inset 取值；用户对观感不满意时，换用已被用户认可的同类现成弹窗比反复调样式更可靠 |:`Border` 非统一色 + `borderRadius` 抛 "uniform colors" 断言;Row `CrossAxisAlignment.stretch` 在无界高度视口抛 "infinite height" | Flutter 规定各边颜色不一致的 Border 不能配圆角;stretch 需要有界高度约束 | 外层 Container 统一色发丝描边(可配圆角)+ 内层 ClipRRect 左色条;Row 外包 `IntrinsicHeight` 让色条取内容高 | 非 uniform 边框/圆角组合与无界高度下 stretch 是 Flutter 布局两大经典坑,容器类 UI 先想约束 |

---

## 9. 禁忌清单

1. **禁改 Isar 嵌入对象字段**（SubStep/ExecutionEntry/Attachment）——schema 冻结。新元数据放 Task 级增量列表（参考 `subStepOrigins` 模式）并跑 `dart run build_runner build` 重新生成 `task.g.dart`。
2. **禁加全局 SelectionArea**（AppShell/MaterialApp builder 层）——右键清空选区 + 劫持嵌套 SelectableText。
3. **禁重新引入 InlineHtmlSyntax** 到 AppMarkdownBody——会吞掉 `<font>` 富文本标签。
4. **禁在侧边栏显示版本号**（用户明确要求移除，仅 Settings About）。
5. **禁恢复已删除主题**：oceanBlue、sakuraPink、blueDark、purpleDark（v1.4.98 用户要求删除）；espresso、deepSea、aubergine（v1.8.0 用户实测后要求删除）。同理，v1.8.0 已删除的字体预设（notoSansSC/poppins/pairInterNoto/pairInterMiSans/pairLoraSerif/pairNunitoWenKai/pairPlexNoto/pairOutfitMiSans 及全部系统字体选项）不得擅自恢复。
6. **禁把 Latte 表面映射回官方 base/mantle 顺序**——light 模式必须 card > surface > bg。
7. **禁用 `git push origin`**（多 push URL 超时即整体失败）。
8. **禁静默吞保存错误**——所有持久化失败必须 snackbar 告知用户。
9. **禁依赖 Ctrl+Enter 等快捷键作为唯一操作入口**——用户曾找不到保存按钮（v1.4.91 教训：显式按钮必须可见）。
10. **禁删测试代替改测试**——断言是契约，架构变更时更新断言。
11. **禁在可能出现中文的 TextStyle 上只设 `fontFamily`**——必须携带 `FontStack` 回退链，否则中文落系统字体破坏混排灰度（v1.5.2 教训）。
12. **禁擅自添加 Mermaid 扩展支持**（v1.5.3 修订：仅禁 Mermaid；LaTeX 已由用户重提并落地，只支持 `$...$` 与 `$$...$$`，不解析 `\( \)`/`\[ \]`）。如用户再重提 Mermaid，先重审无 WebView 前提下的路线再确认。
13. **禁把 GFM alerts 五色语义色硬编码到组件里**——必须经 `AppColors.alertAccent/alertBackground`（亮/暗双套），保证全部 21 主题下可读对比度（v1.5.3）。
14. **禁改 `GfmExtensions.prepare` 管线顺序或去掉结构行豁免**——会导致表格再次退化为字面 `\|` 行（8.19）。
15. **禁用 PowerShell Set-Content/Get-Content 批量改源码文件**——去重/替换脚本会把整个文件压成一行（v1.6.0 曾毁掉 timeline/calendar/reports 三文件，靠 git checkout 恢复）；源码编辑一律用 Edit 工具。

---

## 10. 当前进度与下一步计划

**已完成（近期）**：
- ✅ v1.12.27（已发版）：奶油玻璃 dashboard 主题（glassDashboard：暖炭玻璃阶梯 bg→surface→card + 奶油 primary + 深炭 onPrimary，第 13 款主题）+ ThemePalette.onPrimary 机制（默认白，其余主题零变化）+ 白字压 primary 的 9 处硬编码改读 onPrimary（日历选中态/对勾/spinner）；303 测试全过、双推 `c04236f`、包体 36.0MB
- ✅ v1.12.26（已发版）：Calendar 日期格实体瓷砖质感（顶面受光渐变+镜面高光+斜面边框+层叠投影四层模型，静止→hover→today→selected 递进；今日/选中圆形日期徽章；周末反渐变凹陷；选中日光泽按键+主色光晕）；300 测试全过、双推 `962cc7a`、包体 35.9MB
- ✅ v1.12.25（已发版）：删除可可看板（12 款主题）+ Calendar 月份胶囊工具栏/日面板头部精修 + Activity 状态卡 KPI 化（accent 色条/图标章/accent 数值）+ 清除重复图例；300 测试全过
- ✅ v1.12.24（已发版）：修 TaskListCard 无界高度塌缩（Calendar/Activity 任务列表空白）——IntrinsicHeight 内置组件；301 测试全过（+2 回归）
- ✅ v1.12.23（已发版）：三页任务卡升级 Today 皮肤（TaskListCard 重生：白卡+顶面微亮+左渐变色条）+ Timeline 轨道脊柱 + Calendar 周末微着色 + Activity 统计卡图标章/热力图图例；299 测试全过
- ✅ v1.12.22（已发版）：Timeline/Calendar/Activity 立体感精修——HoverLift 双层 elevation 阴影、时间线发光脊柱（白心彩环节点+状态色渐变线）、日历格 hover/今日渐变/选中投影/表头分隔线、热力图格高光渐变+hover 放大描边；299 测试全过
- ✅ v1.12.21（已发版）：删除奶油/珍珠看板（13 款主题）+ 浅色看板主题透明度修复——Card opacity 控制卡片填充、Interface Glass opacity 缩放列底着色强度；299 测试全过
- ✅ v1.12.20（已发版）：全部浅色主题 Notion 化——暖沙/黛蓝重调（安静画布+发丝线+白卡+墨色文字，暖沙主色换 Notion 棕）并加入 boardTinted 家族（浅色全家 dashboard=参考图观感）；301 测试全过
- ✅ v1.12.19（已发版）：看板主题家族 1→5——新增奶油看板/珍珠看板（浅）+可可看板/午夜看板（暗），boardTinted 机制泛化（列底按语义 accent 着色，浅=白卡浮粉彩列/暗=半透卡渗色）；15 款主题；301 测试全过（+4 签名锚点）
- ✅ v1.12.18（已发版）：新增"墨板 Notion Board"主题——近黑画布+每列按语义 accent 着色+80% 半透明卡片透列色（参考用户提供的 Notion 看板截图）；11 款主题；297 测试全过（+1 签名锚点）
- ✅ v1.12.17（已发版）：主题精简 21→10（删 11 款：8 浅色+双 Latte），默认改黛蓝 inkBlue，遗留色别名重映射锚点，存量用户自动回退；296 测试全过
- ✅ v1.12.16（已发版）：浅色玻璃列底着色化（白卡对比浮现，治暗淡模糊）+ 卡片玻璃自动降透明度主题感知（浅 85%/深 55%）+ HoverLift 静置阴影（三页任务卡立体感）；301 测试全过（+1 lightTheme 默认值）
- ✅ v1.12.15（已发版）：浅色主题观感优化——环境画布常驻（非玻璃 whisper 版/玻璃鲜活版）、侧边栏/内容面板/标题栏三层纸面化、Timeline 标题竖条、Calendar 日面板与 Activity 统计卡浮动化；300 测试全过
- ✅ v1.12.14（已发版）：新增 3 款清新浅色主题——薄荷/晴空/蜜桃（玻璃时代调色设计：真实色相阶梯+border 彩度+色相化文字）；主题数 18→21；300 测试全过（+3 签名锚点）
- ✅ v1.12.13（已发版）：Timeline/Calendar/Activity 任务卡悬停动效——共享 HoverLift 组件（上浮+accent 阴影+边框高亮+click 光标），与 Today 卡片语言一致；297 测试全过（+1 hover_lift_test）
- ✅ v1.12.12（已发版）：Today 画布恢复实色——消除半透明画布带来的毛玻璃雾，玻璃效果保留在列底+卡片；296 测试全过
- ✅ v1.12.11（已发版）：浅色主题玻璃修复——玻璃激活时浅色画布加深（Today 50%/64%、外壳 55%/72%），卡片玻璃亮边浅色改用主题描边色（深色保持白边）；296 测试全过
- ✅ v1.12.10（已发版）：Card Appearance 与 App Interface Glass 完全独立（各自玻璃开关+透明度 0–100%+模糊），删除统一联动 effectiveBoardCardStyle；列底=界面玻璃优先、卡片玻璃兜底（-0.2）；296 测试全过
- ✅ v1.12.9（已发版）：统一材质下 Today Board Cards 滑块恢复可调——直驱全局共享状态（与 Interface Glass 双向同步），玻璃开关仍归 Interface Glass 区；298 测试全过
- ✅ v1.12.8（已发版）：玻璃材质统一——Interface Glass 开启时全 App（面板/画布/列底/卡片/KPI/QuickAdd）共用一个透明度与模糊（列底-0.2 阶梯），Today Board Cards 独立控件禁用并提示；298 测试全过（+2 effectiveBoardCardStyle）
- ✅ v1.12.7（已发版）：Interface Glass 贯通 Today 页——画布/列底跟随 appGlass.opacity、侧边栏填充跟随透明度滑块，界面玻璃在 Today 主区域实时可见；296 测试全过
- ✅ v1.12.6（已发版）：玻璃效果可见性修复——Today 玻璃时列底半透明+光晕×1.8、KPI/QuickAdd 跟随卡片样式；全局画布加深+光晕加强+玻璃面板白色亮边、开启默认透明度 0.75；296 测试全过
- ✅ v1.12.5（已发版）：全局界面玻璃——Interface Glass 设置区（开关/透明度 40–100%/模糊 4–30），AppShell 环境画布+三面板 GlassPanel，主题 surface/card 半透明（scaffold 恒不透明），普通卡片全应用自动毛玻璃；296 测试全过（+15，app_glass_test.dart）
- ✅ v1.12.4（已发版）：玻璃态强度可调——Blur strength 滑块（sigma 4–30 默认 14，玻璃关时禁用），TaskCard 与 Settings 预览共用；281 测试全过
- ✅ v1.12.3（已发版）：Settings 新增 Today Board Cards 区——卡片透明度滑块（30%–100%）+ 玻璃态开关（BackdropFilter 磨砂+亮边，开启时 100% 透明度自动降 55%）+ 迷你画布实时预览；`board_card_style_provider` 持久化；280 测试全过（+13，board_card_style_test.dart）
- ✅ v1.12.2（已发版）：note 预览可读性修复（12.5px/w500/78% 色/3 行/图标加大）；267 测试全过、双推 `26edff7`、包体 35.9MB；文档轮：README 中英增补「阶段 8 看板 Dashboard」、handoff 测试数同步 267/25 文件、清理 v1.11.0~v1.12.1 旧版 zip（保留 v1.12.2）、`.zcode/` 入 gitignore
- ✅ v1.12.1（已发版）：看板卡片新增最近日志预览块（类型着色图标 + 2 行内容，位于描述与 chips 之间）；267 测试全过、双推 `44a1c46`、包体 35.9MB
- ✅ v1.12.0（已发版）：看板卡片预览内容升级——描述 3 行预览、底部统计行（📎 附件数/💬 日志数/子任务进度环）、优先级徽章常显；267 测试全过、双推 `fbe9051`、包体 35.9MB
- ✅ v1.11.3（已发版）：Today 看板浅色主题二次修——画布向 border 加深（38%→52% 渐变）、玻璃列提实 white 72%、浅色阴影/洗底加强；深色主题零改动；267 测试全过、双推 `d14785c`、包体 35.9MB
- ✅ v1.11.2（已发版）：修 Today 看板最右列被裁切（LayoutBuilder 移入内边距内侧按真实宽度均分列宽）；267 测试全过、双推 `d91be36`、包体 35.9MB（注：`outputs/` 中旧版解包目录已被用户清理，后续打包的使用说明.txt 从 Release 目录沿用，首次打包需从 v1.11.1+ 的 zip 或存档取回）
- ✅ v1.11.1（已发版）：Today 看板浅色主题「纸感」修复——bg 灰蓝画布 + 纯白卡片 + 玻璃列，删页头色带、整列洗底缩到顶部，边框/阴影加强；267 测试全过、双推 `5d0484c`、包体 35.9MB
- ✅ v1.11.0（已发版）：Today 看板视觉质感升级（环境光晕/KPI 渐变卡+图标章/列渐变洗底/滚动条）+ 维度切换 Status/Project/Priority（拖拽跨列=改对应属性、列头"+"按维度继承）；267 测试全过（+3 契约）、双推 `f954ea3`、包体 35.9MB
- ✅ v1.10.0（已发版）：Today 页看板化改版——4 张 KPI 统计卡 + 四列看板（To Do/In Progress/Done/Blocked，拖拽跨列改状态、列内"+"快速添加、快捷筛选 pills）；保留拖卡片转子任务交互与快速添加栏；Archived 归入 Done 列；264 测试全过（+10 看板契约）、双推 `0351600`、包体 35.9MB
- ✅ v1.9.3（已发版）：Reports 报告总结优化——In Progress 一句话总结、进度明细近一周（7 天）聚焦+超一周一句话历史、下期计划只含未完成任务且不分解；254 测试全过（+1 契约）、双推 `5001225`、包体 35.9MB
- ✅ v1.9.2（已发版）：Timeline 排序反转为最新在最上；253 测试全过、双推 `2704819`、包体 35.6MB
- ✅ v1.9.1（已发版）：Timeline 时间列改日期+时间两行（yyyy-MM-dd/HH:mm）；253 测试全过、双推 `26aa546`、包体 35.6MB
- ✅ v1.9.0（已发版）：删"系统默认"预设、Inter×MiSans 设为应用默认（预设仅剩 3 配对）+ Timeline 任务标题画线对齐 Today；253 测试全过、双推 `23344f1`、包体 35.6MB
- ✅ v1.8.0（已发版）：按用户实测反馈精简——删 3 深色主题（共 18）+ 字体预设裁至 系统默认+3 配对；修复 AI 配置不自动加载（异步恢复竞态锁存空值）+ Activity/Calendar 页 Archived 缺画线；253 测试全过（契约同步）、双推 `a2c7ed6`、包体 35.6MB
- ✅ v1.7.0（已发版）：6 新主题（青瓷/黛蓝/胭脂 + 深咖啡/深海蓝/墨紫，共 21）+ 3 字体配对（Inter×MiSans、Plus Jakarta Sans×思源黑体、Lexend×思源黑体）+ 修复 Plex/Outfit 拉丁下载分支缺失；255 测试全过（+13 契约）、双推 `29bedd0`、包体 35.7MB
- ✅ v1.6.5（已发版）：Custom 日期范围单弹窗选择（Daily/Weekly 同款日历网格，点开始日→点结束日→OK，同日双击=单日范围）；242 测试全过（+5 契约）、双推 `63a97b4`、包体 35.6MB
- ✅ v1.6.4（已发版）：Custom 日期范围改用 Daily/Weekly 同款单日期弹窗（两步 start→end，任一步取消整体中止，API 不变三处零改动）；241 测试全过（+4 契约）、双推 `b1836be`、包体 35.6MB
- ✅ v1.6.3（已发版）：日期范围选择器定稿——480×500 布局 ×1.1 → 528×550 近原生弹窗（倍率 1.5×→1.1×、卡片对齐铬层、按钮统一、文案全 i18n）；239 测试全过（+1 组合回归）、双推 `23a9036`、包体 35.7MB
- ✅ v1.6.2（已发版）：日期范围选择器放大 1.5×（FittedBox 等比放大，视觉 660×690，紧凑无留白）；238 测试全过、双推 `a1c6d06`、包体 35.7MB
- ✅ v1.6.1（已发版）：AI Parse 总结会话级（跨页不打断/新结果落地才替换旧总结/输入附件结果全量跨页保持）+ Copy Markdown + Save .md/.html 下载；Tab 改光标处插入 2 空格（多行选区/反缩进不变）；Timeline/Calendar 默认近 30 天；日期范围选择器全屏根因修复（紧凑 MediaQuery 覆写，踩坑 8.26）；237 测试全过（+4）、双推 `db44245`、包体 35.7MB
- ✅ v1.6.0（已发版）：七项需求——Nord Night/Warm Sand 两新主题（共 15）+ IBM Plex Sans/Outfit 字体配对；AI 配置防抖自动保存；Timeline/Calendar 默认近一周；`showAppDateRangePicker` 三处接入；AI Parse 提示词框+文件解析（docx/xlsx/pptx/pdf/eml 等，150MB 上限）+ 邮件 playbook 总结模式；Tab 整行缩进 6 项回归锁定；233 测试全过（+6）、双推 `6befd97`、包体 36.1MB
- ✅ v1.5.10：全页面 Tab 缩进收口（AI Prompts 编辑器换 indent focusNode）
- ✅ v1.5.9：AI Prompts 草稿跨页保持 + MarkdownToolbar；报告去 Overall、摘要结构化、HTML `~` 转义
- ✅ v1.5.8：AI Prompts 打磨（可调大小/Settings 字体/质感）；✅ v1.5.7：AI Prompts 页面
- ✅ v1.5.6：报告打磨（Headline 列表/去 sub-steps/10 天聚焦）
- ✅ v1.5.5-3：alerts GitHub 风格/LaTeX TextScaler/表格 WidgetSpan/GFM 四能力
- 双远程同步至 `5001225`（v1.9.3）

**进行中**：
- 用户实机验证 v1.9.3：Reports 页重新生成 AI 报告，检查 In Progress 一句话、进度明细近一周聚焦、下期计划不分解三项新格式。应用已在运行（v1.9.3 exe）。
- 本仓库由旧工作区迁至 `F:\gitee\taskflow\TaskFlow` 后首次构建：`build/` 内旧 CMake 缓存指向旧路径导致 "does not match the source" 报错，删 `build/` 重来即愈；`windows/flutter/ephemeral/.plugin_symlinks` 陈旧符号链接致 errno 183，同删即愈。

**待办/已知局限**：
- **疑似 UI 缺陷（待排查）**：快速添加任务后列表偶发不刷新，重启后自愈（v1.5.2 验证时由 ComputerUse 发现，未复现定位）。
- 可选链中**表格与公式均为 WidgetSpan**：不参与文字选区、Ctrl+C 复制时丢失（已接受；右键 Copy as Markdown 始终复制完整原始源码，测试用 toPlainText 断言时需预期占位符 `\uFFFC`）。
- alerts 在可选链为降级形态（▎标签+槽线文本），与 AppMarkdownBody 的卡片容器存在形态差异——若用户报“预览与保存后不一致”，alerts/脚注/Reports 块边距是三个排查入口。
- LaTeX 不解析 `\( \)`/`\[ \]`；货币边界规则下 `$x and $y` 这类文本仍会被当公式（规范所定，不可避）。
- ComputerUse 验证遗留临时文件：`f:\gitee\voice_record_summary_ai` 下 `tf_shot.ps1`、`tf_editor1~3.png`（可删）。
- `app_colors.dart` 底部遗留硬编码别名（lightBg/darkBorder 等）被部分代码以 `isDark ? darkX : lightX` 直接引用，不跟随当前主题色相——改浅色主题时需同步这些别名。
- GitHub 推送偶发超时（环境问题，重试即可）。
- Google Drive 同步无文件冲突合并策略（附件为不可变 uuid 文件天然无冲突；快照为 merge-by-uid）。

---

## 11. 给接手机型的建议

1. **先读后动**：顺序 = 本文档 → `lib/core/theme/` → `lib/presentation/shared/`（渲染三件套）→ `lib/data/services/`。
2. **每轮交付完整闭环**：改码 → analyze → test → 双处升版 → 构建（记得杀进程后等 20 秒）→ 提交 → 双推 → 打包 → 启动。用户期待一轮完成。
3. **用户对视觉细节敏感**：按钮排布、亮度、清晰度、留白都可能被点名；改动前先想"桌面端惯例"（主操作居右、等高对称、显式入口）。
4. **测试是安全网**：190 个测试覆盖渲染契约、报告格式与字体迁移，改前先跑，改后必过。
5. **长期记忆系统里有大量项目约定**（主题、报告规范、推送纪律等），接手时先查。
6. **不要主动创建文档文件**（包括本文件的更新除外）——用户未要求时不写 README。

---

## 12. 交接记录

| 日期 | 交班模型 | 接班模型 | 本次会话主要变更 |
|---|---|---|---|
| 2026-08-26 | Qoder（本会话，v1.4.85→v1.5.2） | 待定 | 字体排版设置、可调节图片预览、编辑对话框粘图、Drive 同步加固（两阶段/占位文件/路径自愈合）、报告全量日志+清单版式、内联编辑流程、Catppuccin 主题体系、主题精简与 Latte 清晰度修复、中英字体配对四预设（含内置 MiSans）、扩展 Markdown（脚注/上下标/高亮样式修复）、v1.5.1 块间距修正（标题紧贴/段-列表无空行）、v1.5.2 字体升级 Manrope×MiSans（包体 42→35.8MB，FontStack 混排链，双 Provider 补中文回退） |
| 2026-08-26 | Qoder（本会话，v1.5.2→v1.5.3 代码+构建） | 待定 | GFM 四能力两链补齐：表格（字面 `\|` 根因修复：prepare 管线 + 硬化豁免 + 样式注入 / 可选链 CJK 双宽对齐列）、任务清单（checkbox hoist + ☐/☑ 只读字形）、GFM Alerts（大小写敏感语法 + 主题化容器/五色集中定义 + 可选链降级标签槽线，普通引用零影响）、LaTeX 解禁落地（严格定界防货币误判、多行 `$$` 展平、可选链 WidgetSpan、错误回退原文、流式自动重渲染）、`<br>` 窄义支持、report_service 表格归一委托共享实现；新增 23 项契约测试（共 213）；**发版后半程未完成：实机验证（ComputerUse 两次中断）→ 提交 → 双推 → 打包 → 启动，接手续做，步骤见第 10 节进行中栏** |
| 2026-08-26 | 接班模型（本会话，v1.5.3 发版闭环收尾） | 待定 | 验证 v1.5.3 实现完整性（analyze 0 error、213 测试全过）→ 提交 `ceb470f`（13 文件 +1218/-148）→ Gitee/GitHub 显式单 URL 双推均一次成功 → 打包 `TaskFlow-v1.5.3-windows-x64.zip`（35.9MB，基线 35.8MB +0.1MB 来自 KaTeX 字体）→ 启动 exe；实机用例目检留给用户 |
| 2026-08-26 | 接班模型（本会话，v1.5.3→v1.5.4 渲染打磨轮） | 待定 | 用户实机反馈三问题：①可选链表格 ASCII 网格观感差且 CJK 列错位 → 经选项确认改 WidgetSpan 真实 Table（删 displayWidth/padCell，踩坑 8.24）；②checkbox 字形太弱 → 两链换 Material 图标公共组件 TaskCheckboxGlyph；③alerts 观感 → 类型图标+发丝描边+ClipRRect 左色条（踩坑 8.25：非 uniform Border 配圆角、无界高度 stretch 两连崩）、可选链槽线 `▎`。表格/checkbox 契约断言迁移为 widget 断言；analyze 0 error、213 测试全过；提交 `5788652` 双推一次成功；打包 v1.5.4 35.9MB；exe 已启动待用户目检 |
| 2026-08-26 | 接班模型（本会话，v1.5.4→v1.5.5 参考图对齐轮） | 待定 | 用户提供 GitHub 参考截图：alerts 重构为纯淡色圆角卡（去掉 v1.5.4 的左色条+描边）+ 首字母大写标签 + GitHub 系图标（火焰/报告标），两链标签同步 title case（测试断言同步，注意测试源码须保持大写 `[!NOTE]`）；LaTeX 排版根因定位为 flutter_math_fork 自绘不响应 TextScaler → 两链显式乘 `textScalerOf(context)`。213 测试全过；提交 `6f3e7ef` 双推一次成功；打包 v1.5.5 35.9MB；exe 已启动 |
| 2026-08-26 | 接班模型（本会话，v1.5.5→v1.5.6 报告打磨轮） | 待定 | 用户四需求：①仪表盘 Headline 列表化（`_groupHeadline`→`_groupHeadlines` ≤3 条 `<br>` 连接，提示词模板+规则+自检三处同步）；②执行摘要去 sub-step 比例（MD/HTML/双语提示词）；③进度明细 10 天近因聚焦（formatTaskData 以期终为基准分档，旧日志标 context-only，提示词要求压成"早期背景："一句计入 5 条上限）；④HTML 导出由 MD 源渲染天然一致（确认 toHtml 仅测试用，做 lockstep 更新）。新增 4 项契约测试（共 217）；提交 `2acf634` 双推一次成功；打包 v1.5.6 35.9MB；exe 已启动 |
| 2026-08-26 | 接班模型（本会话，v1.5.6→v1.5.7 AI Prompts 页） | 待定 | 新增 AI Prompts 页面：`ai_prompts_screen.dart`（输入→生成→MD 渲染→Copy prompt 抓代码块）+ 路由 `/prompts` + 侧边栏项；`AiService.generatePrompt`（system=用户提供的 playbook 原文常量，user=`# 用户需求`+输入，temp 0.5/maxTokens 2000/响应超时 120s×3 推理模型）；顺带修复 Generate 按钮不随输入启用的真实缺陷（AnimatedBuilder）与侧边栏 "AI Prompts" 标签溢出（Flexible+ellipsis，8.7 模式）；5 项契约测试（共 222）；提交 `84deae2` 双推一次成功；打包 v1.5.7 35.9MB；exe 已启动 |
| 2026-08-26 | 接班模型（本会话，v1.5.7→v1.5.8 AI Prompts 打磨轮） | 待定 | 用户四需求：①输入框拖拽调高（grip 120–420px）；②输入改 MarkdownEditorField（Write/Preview + 预览 sheet）；③字体接 Settings 双链路（输入 applyInputTypography、预览/输出 applyContentTypography，复用既有 Provider 不另起炉灶）；④质感（输出卡片 surface+圆角 12+RESULT 头、代码块淡底面板+边框、预览输出同 sheet WYSIWYG）。测试加 Write/Preview 存在断言（共 222）；提交 `56a2ce5` 双推一次成功；打包 v1.5.8 35.9MB；exe 已启动 |
| 2026-08-26 | 接班模型（本会话，v1.5.8→v1.5.9 五项优化轮） | 待定 | ①AI Prompts 草稿跨页保持（ShellRoute 销毁 widget → 输入/结果入会话级 StateProvider，initState 恢复 + listener 持久化）；②输入区加 MarkdownToolbar；③报告移除 Overall（MD/HTML/双语提示词/_overallRag/overallS/`l.overall` 全链清除）；④执行摘要结构化（_firstSummary→_summaryLines，每行摘要独立 `  - ` 要点，MD/HTML/提示词同步）；⑤导出 HTML `_escapeTildesForHtml`（markdown 包 StrikethroughSyntax 连单 `~` 都匹配致误判删除线，全量转 `&#126;`，StyledHtml+EmailHtml 两路径）。4 项契约测试（共 226）；提交 `cc8c322` 双推一次成功；打包 v1.5.9 35.9MB；exe 已启动 |
| 2026-08-26 | 接班模型（本会话，v1.5.9→v1.5.10 Tab 缩进收口） | 待定 | 用户要求所有页面输入框支持 Tab 缩进。全量审计：Work Log（_onInputKey）/执行日志（内联 onKeyEvent）/AI Parse/Reports/建任务/编辑任务对话框/MarkdownEditorField 默认节点均已支持；唯一缺口 AI Prompts 编辑器（裸 FocusNode）→ 换 `markdownIndentFocusNode(_inputController)`；单行字段（搜索/配置）保持 Tab=焦点导航。1 项 Tab 契约测试（共 227，注意 enterText 光标在文末，断言前须显式置 caret）；提交 `b83b60a` 双推一次成功；打包 v1.5.10 35.9MB；exe 已启动 |
| 2026-08-26 | 接班模型（本会话，v1.6.4→v1.6.5 单弹窗范围选择轮） | 待定 | 用户反馈两步两次弹窗 → 自定义单弹窗 `_RangePickerDialog`（复用 Daily/Weekly 同款 CalendarDatePicker 网格：点开始→点结束→OK，同日双击=单日范围，早于开始日原地重开，Cancel 中止，预填范围直接可 OK）；头部主色淡染+实时范围头条+Start/End 状态 chips（短日期格式；标题 FittedBox、chips Wrap 防溢出——测试环境 Ahem 字体踩坑）；5 项契约测试（共 242）；提交 `63a97b4` 双推一次成功；打包 v1.6.5 35.6MB；exe 已启动 |
| 2026-09-02 | 接班模型（本会话，v1.6.5→v1.7.0 主题+字体轮） | 待定 | 用户两需求：①三浅三深六新主题（青瓷/黛蓝/胭脂 + 深咖啡/深海蓝/墨紫，共 21，枚举按组插入四 switch 同步，dustyRose 初稿 card 亮度低于 bg 违反浅色层级经测试驱动物调为 bg F6F0F0/card FAF3F3）；②三字体配对 Inter×MiSans、Plus Jakarta Sans×思源黑体、Lexend×思源黑体（google_fonts 下载零包体），顺带修复 v1.6.0 IBM Plex Sans/Outfit 漏注册 `_googleFontTextTheme`（真缺陷）；新增 theme_palette_test 11 项 + font_upgrade_test 2 项契约（共 255，含 GoogleFonts.asMap 家族存在性验证）；迁移环境踩坑：旧 build/ 的 CMakeCache 指向旧工作区路径 + 陈旧 .plugin_symlinks errno 183，均删目录重建即愈；提交 `29bedd0` 双推一次成功；打包 v1.7.0 35.7MB；exe 已启动 |
| 2026-09-02 | 接班模型（本会话，v1.7.0→v1.8.0 精简+修复轮） | 待定 | 用户实测后四需求：删三深色主题（保留三浅色，共 18）；字体预设裁至 系统默认+3 配对（systemFonts 列表整体删除、app.dart 孤儿下载分支清理、内容/输入下拉自动收窄）；修复 AI 配置自动加载竞态（AiConfigNotifier.restored 标志 + _ensureLoaded 门闩推迟，防首帧锁存空默认值且防后续 autosave 把存量配置覆盖成空）；统一 Archived 渲染（heatmap 1 处 + calendar 2 处 isCompleted 补 archived 判定，与 Today 看板/README 约定对齐）；契约测试同步更新（font_upgrade/font_settings/theme_palette，共 253）；提交 `a2c7ed6` 双推一次成功；打包 v1.8.0 35.6MB；exe 已启动 |
| 2026-09-02 | 接班模型（本会话，v1.8.0→v1.9.0 默认字体+Timeline 画线轮） | 待定 | 用户两需求：①删"系统默认"预设，Inter×MiSans 设为应用默认（defaultFont→interMisans，旧 'system' id 未知即回退默认天然迁移；预设 4→3）；②Timeline `_TimelineItem` 标题补 completed/archived lineThrough+0.4 变淡（含 decorationColor），状态点/徽标不动；契约测试同步（defaultFont 断言、ids 白名单、'system' 入 removed 清单，共 253）；提交 `23344f1` 双推一次成功；打包 v1.9.0 35.6MB；exe 已启动 |
| 2026-09-02 | 接班模型（本会话，v1.9.0→v1.9.1 时间列日期轮） | 待定 | 用户需求：Timeline 左侧只有时间希望有日期 → `_TimelineItem` 时间列 52px 单行 HH:mm 改 96px 两行（yyyy-MM-dd 上/HH:mm 下，IntrinsicHeight 内 Column 天然取内容高，行间 2px）；宽度按 140% 字号缩放最坏情况（labelSmall 11px→15.4px×10 字符≈92px）留余量；纯展示改动无契约测试变更（253 不变）；提交 `26aa546` 双推一次成功；打包 v1.9.1 35.6MB；exe 已启动 |
| 2026-09-02 | 接班模型（本会话，v1.9.1→v1.9.2 时间线倒序轮） | 待定 | 用户需求：Timeline 上面是最近时间、下面为久远时间 → `_filterTasks` 排序比较器翻转（createdAt 降序），isLast 竖线逻辑不动；纯展示改动无契约测试变更（253 不变）；提交 `2704819` 双推一次成功；打包 v1.9.2 35.6MB；exe 已启动 |
| 2026-09-18 | 接班模型（本会话，v1.9.2→v1.9.3 报告总结优化轮） | 待定 | 用户三需求：①执行摘要 In Progress 每任务一行=加粗标题+" — "+一句话总结（中英提示词输出模板+分节规则+回退模板 toMarkdown/toHtml 同步，取 AI 摘要首行为该句）；②进度明细近因聚焦 10→7 天（formatTaskData recentCut+context-only 标签+中英提示词，超一周压成"早期背景："一句历史总结、详情条目改为任务详细描述）；③下期计划只含未完成任务且每任务一行禁止分解（删中英"可分解为多个行动行"指令，任务列模板去"分解后的子任务"措辞）；新增 In Progress 单行契约测试+更新 7 天分档契约（253→254，踩坑：整周报告期 start=end−7d 时"近期但期外"分档为空集，测试改用 07-15→07-20 短周期构造）；analyze 0 error、254 测试全过；提交 `5001225` 双推一次成功；打包 v1.9.3 35.9MB（DLL+使用说明已在 Release 目录未重做）；exe 已启动 |
