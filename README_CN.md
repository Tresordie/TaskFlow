# TaskFlow

[English](README.md) | **中文**

面向硬件测试工程师的跨平台任务管理应用，基于 Flutter 构建。

## 快速开始

### 环境要求

- Flutter SDK >= 3.4.0 (https://docs.flutter.dev/get-started/install)
- Dart SDK >= 3.4.0

### 安装与运行

```bash
# 1. 生成平台相关项目文件
flutter create . --platforms=windows,macos,ios --org com.taskflow

# 2. 安装依赖
flutter pub get

# 3. 运行代码生成（Isar + Riverpod）
dart run build_runner build --delete-conflicting-outputs

# 4. 运行应用
flutter run -d windows   # 或 -d macos
```

### 项目结构

```
lib/
├── main.dart                          # 入口（桌面 chrome 保护）
├── app/
│   ├── app.dart                       # MaterialApp + 主题 + 字体缩放
│   └── router.dart                    # GoRouter 导航
├── core/
│   ├── theme/
│   │   ├── app_colors.dart            # 18 套主题色板 + 优先级颜色
│   │   └── app_theme.dart             # 每套色板的 ThemeData
│   └── markdown/
│       ├── latex_support.dart         # Markdown 中的 $..$ / $$..$$ LaTeX
│       ├── rich_markdown.dart         # ++下划线++ / ==高亮== / <font …>
│       ├── line_breaks.dart           # 硬换行、缩进保留、列表嵌套归一化
│       └── html_export.dart           # Markdown → 独立/邮件 HTML
├── data/
│   ├── models/task.dart               # Task, ExecutionEntry, SubStep (Isar)
│   ├── database/app_database.dart     # Isar 实例管理
│   ├── repositories/task_repository.dart  # 数据访问层
│   └── services/
│       ├── attachment_service.dart    # 附件磁盘拷贝
│       ├── ai_service.dart            # OpenAI 兼容聊天客户端
│       ├── report_service.dart        # 周期聚合 + MD/HTML 导出
│       ├── backup_service.dart        # JSON 快照 / 恢复
│       └── sync_service.dart          # Google Drive 文件夹同步
├── providers/
│   ├── task_providers.dart            # 任务状态 + 过滤器
│   ├── theme_provider.dart            # 持久化主题模式
│   ├── font_provider.dart             # 持久化字体 + 缩放
│   ├── ai_provider.dart               # 持久化 AI 端点配置
│   └── sync_providers.dart            # 备份 + 同步 Notifier
└── presentation/
    ├── shared/                        # App Shell, 自定义标题栏,
    │                                  #   MarkdownEditorField（Write/Preview）,
    │                                  #   MarkdownToolbar, SelectableMarkdownBody
    ├── task_board/                    # 今日看板 + 快速添加
    ├── task_detail/                   # 详情、执行日志、编辑对话框
    ├── timeline/  calendar/  heatmap/ # 时间线视图
    ├── ai_parse/                      # AI 笔记解析 → 任务
    ├── reports/                       # 报告生成器 + 预览
    ├── work_log/                      # 工作日志
    └── settings/                      # 主题/字体/AI/备份与同步

test/
├── core_logic_test.dart               # 报告周期、AI 配置、枚举
└── widget_test.dart                   # LaTeX 渲染、标题栏
```

## 功能特性

### 阶段 1 — 核心任务管理
- 任务 CRUD，支持优先级（P0-P3）和状态跟踪
- 执行日志：带时间戳的条目，支持类型（Note/Pass/Fail/Blocked）、Markdown + LaTeX 渲染、编辑/删除、文件与图片附件
- 任务内子步骤清单
- 今日看板、时间线、日历和热力图视图
- 快速添加栏（优先级 + 截止日期）
- 18 套颜色主题——低饱和浅色（青瓷 / 黛蓝 / 胭脂）及此前的基础色板与 Catppuccin 系列；3 种精选中英混排字体配对（Inter × MiSans、Plus Jakarta Sans × 思源黑体、Lexend × 思源黑体）+ 系统默认与自定义字体；全局字号缩放（80–140%）
- 响应式布局：桌面侧边栏，移动端底部导航
- 基于 Isar (NoSQL) 的本地优先持久化

### 阶段 2 — AI 笔记解析
- 在设置 → AI 助手中配置任意 OpenAI 兼容端点（DeepSeek / OpenAI / Qwen / Ollama…），支持连接测试
- 粘贴原始笔记（会议记录、测试日志、聊天摘录）→ LLM 提取结构化任务（标题、描述、优先级、标签、子步骤）
- 通过复选框审阅解析结果，一键批量创建

### 阶段 3 — 报告生成
- 按日 / 周 / 月 / 年聚合任务 + 执行日志
- 仪表盘统计：涉及 / 已完成 / 进行中 / 逾期 / 完成率 / Pass-Fail-Blocked 计数 / 子步骤进度
- 逐任务复选框选择器和项目/标签/状态/优先级过滤器
- AI 驱动完整报告生成（OpenAI 兼容 LLM），失败时回退到确定性模板
- Archived 任务自动排除在报告之外
- 实时 Markdown 预览；导出为 `.md` 或独立样式 `.html`
- 导出路径：`Documents/TaskFlow/reports/`

### 阶段 4 — 工作日志
- 专用工作日志，支持富文本 Markdown 输入（Write/Preview 切换）
- AI 要点总结（跨所有记录）
- 右键"Copy as Markdown"复制任意记录
- 按日期 / 项目 / 关键词过滤

### 阶段 5 — 备份与同步
- 一键 JSON 备份（任务、日志、子步骤、附件引用）到 `Documents/TaskFlow/backups/` 或任意位置
- 恢复支持 **完整恢复**（替换全部）和 **合并**（按 task uid 更新/插入）
- Google Drive 同步：通过 Drive-for-Desktop 镜像文件夹（`TaskFlow/taskflow_sync.json`）— 推送 / 拉取 / 自动方向，无需 API 凭据

### 阶段 6 — 体验优化
- 任务看板交错入场动画（flutter_animate）
- Archived 任务展示与 Completed 一致（绿色勾选 + 标题划线），标题下方显示状态标签
- 粘贴内容的健壮 Markdown 渲染：自动规范化 CRLF 换行和不可见 Unicode 空格（不间断空格 / 全角空格），从浏览器或其他应用复制的列表也能正确渲染
- 桌面专属 chrome 保护（iOS/Android 跳过自定义标题栏和 window_manager）
- 单元 + Widget 测试套件（`flutter test`）：报告周期计算、AI 配置、LaTeX 渲染、标题栏

### 阶段 7 — 统一富文本输入与记录展示
- **所有输入区**（工作日志、执行日志及编辑对话框、任务描述创建/编辑对话框、AI 解析笔记、报告编辑器）均支持 Markdown + 富文本输入，带即时 **Write/Preview 切换**——预览使用与保存内容**相同的样式表**（真正的 WYSIWYG“输入即预览”）
- 格式工具栏：H1–H3、加粗 / 斜体 / 删除线、`++下划线++`、`==高亮==`、`<font color>` 与 `<font size>`、引用、超链接、任务清单、无序/有序列表、行内代码、围栏代码块、缩进 / 取消缩进
- **Tab / Shift+Tab**：Tab 在当前行行首缩进（始终可见）；多行选中时整块缩进/取消缩进并保持选中（可连续按）；列表项每按一次 Tab 嵌套一级
- 与 `workreport.html` 一致的预览效果：段落行首缩进在渲染中保留（NBSP 硬化），缩进不足的子项自动归一化嵌套到父级列表项下（基于缩进的嵌套语义）
- **所有已保存记录**（工作日志条目、AI 总结、执行日志笔记、任务描述、AI 解析任务描述、报告预览、总结历史）均以 Markdown 预览方式展现，支持**鼠标拖动整篇选中**，右键菜单提供 **“Copy as Markdown”** 复制原始 Markdown 源码

## 数据位置

| 内容 | 路径 |
| --- | --- |
| 数据库 (Isar) | `Documents/taskflow.isar` |
| 附件 | `Documents/TaskFlow/attachments/` |
| 报告 | `Documents/TaskFlow/reports/` |
| 备份 | `Documents/TaskFlow/backups/` |
| 设置 | Windows 注册表 `HKCU\Software\com.taskflow\taskflow` / macOS 偏好设置 |

## 路线图（规划中）

- 完整 Google Drive OAuth 同步 (googleapis) 作为文件夹同步的替代方案
- 周期性任务和提醒
- 从测试工位导出 CSV 导入
