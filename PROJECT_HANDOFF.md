# PROJECT_HANDOFF.md — TaskFlow

> 本文档是 AI 模型接力开发的交接文档（活文档）。**接班模型必须先读本文档再动手改代码。**
> 最后更新：2026-09-02 · 当前版本 **v1.9.2**（已发版：Timeline 排序反转为**最新在最上、久远在底下**（createdAt 降序）；253 测试）

---

## 0. 快速上手（TL;DR）

- **项目**：TaskFlow —— Flutter Windows 桌面任务管理应用，面向硬件测试工程师（NPI 电动自行车项目）的个人任务/日志/周报工具。
- **位置**：`outputs/taskflow/`（工作区根 = `c:\Users\Administrator\.qoderworkcn\workspace\mrtw67znp8zrkqp4`）。
- **跑起来**：`cd outputs/taskflow && flutter run -d windows`（或 `flutter build windows --release` 后运行 `build\windows\x64\runner\Release\taskflow.exe`）。
- **发版闭环（每次变更必做）**：升版本（`pubspec.yaml` + `lib/core/version.dart` 的 `kAppVersion` **必须同步**）→ `flutter test`（253 个）→ 构建 → `git commit` → **显式单 URL 双推** GitHub + Gitee → `Compress-Archive` 打包 zip 到 `outputs/` → 启动 exe 验证。
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
│   │   ├── theme/app_colors.dart # ThemePalette 定义（18 个主题调色板）+ 遗留硬编码别名
│   │   ├── theme/app_theme.dart  # AppThemeMode 枚举（label/labelZh/palette/brightness）+ buildTheme
│   │   ├── theme/font_stack.dart # 中英混排链单一事实源（v1.5.2，拉丁/中文/回退链常量）
│   │   ├── markdown/             # html_sanitize（HTML混入清洗）、line_breaks（硬换行硬化+结构行豁免）、rich_markdown（含上下标语法）、latex_support（严格定界+多行展平）、gfm_extensions（alerts 大小写敏感语法/任务清单 checkbox hoist/`<br>`/prepare 管线）、table_support（多行行归一+列宽）
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
├── test/                         # 20 个测试文件，253 个测试（含 extended_markdown/selectable_spacing/font_upgrade/gfm_extensions/theme_palette 契约）
└── pubspec.yaml                  # version 字段与 kAppVersion 必须同步；fonts + FONT_LICENSES.md 声明
```

发布包与源码同级：`outputs/TaskFlow-vX.Y.Z-windows-x64.zip`（v1.0.0 → v1.5.2 全保留）。

---

## 4. 运行 / 构建 / 测试 / 部署

```powershell
cd outputs\taskflow
flutter test                                    # 253 个，约 30–40 秒
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
- **报告生成**：`report_service.dart` —— `formatTaskData` 把任务描述（截断 2000 字）+ **全部执行日志**（期内条目与近 10 天条目为主体完整投喂，超 10 天的旧条目标注 `(older than 10 days — context only)`，旧文本每任务上限 12000 字符）喂给 AI；推理模型走流式 `_chatStream`（180 秒块间隔超时，不限总时长）；AI 失败回退确定性模板。输出 5 章节；v1.5.6 起仪表盘 Headline 为 `<br>` 列表（≤3 条）、执行摘要无 sub-step 比例、进度明细聚焦近 10 天日志。
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
3. **主题体系**：18 个主题（v1.8.0）= 8 浅色（indigoLight/freshGreen/sunsetOrange/lavenderPurple/warmSand + v1.7.0 celadon 青瓷/inkBlue 黛蓝/dustyRose 胭脂）+ 2 暗色（dark/nordNight）+ 8 Catppuccin。已删除：oceanBlue、sakuraPink、blueDark、purpleDark（v1.4.98）及 v1.7.0 曾上线的 espresso/deepSea/aubergine（v1.8.0 用户实测后要求删除）。主题按 `mode.name` 字符串持久化，删除枚举值安全（回退默认）；枚举按组插入（浅接 warmSand 后、深接 nordNight 后），Settings 列表/亮度/GFM alert 色自动适配。
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
- 双远程同步至 `2704819`（v1.9.2）

**进行中**：
- 用户实机验证 v1.9.2：Timeline 最新任务在最上。应用已在运行（v1.9.2 exe）。
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
