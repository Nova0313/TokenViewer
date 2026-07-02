# TokenViewer

<p align="center">
  <img src="images/ui.png" width="160" alt="TokenViewer 图标">
</p>

<p align="center">
  原生 macOS 菜单栏应用与桌面小组件，查看 Claude Code 和 Codex 的本地额度。
</p>

> TokenViewer 直接读取本机日志，不上传日志、额度或账号信息。

## 功能

- 显示 Codex 短期（通常为 5 小时）和长期（通常为 7 天）额度、剩余百分比与重置时间
- 尝试读取 Claude Code 本地日志中的兼容额度字段
- 在菜单栏显示所有可用额度中的最低剩余百分比
- 支持手动刷新，以及 1、5、15、30 或 60 分钟自动刷新
- 自动发现本机安装的 Claude Code 和 Codex
- 支持添加、移除、排序服务，并分别控制是否同步到小组件
- 提供可配置的 1×1、1×2 仪表盘小组件和额度宠物小组件
- 点击小组件可直接打开 TokenViewer

| 额度充足 | 额度适中 | 额度紧张 |
| :---: | :---: | :---: |
| <img src="images/high.png" width="220" alt="额度充足时的宠物小组件"> | <img src="images/normal.png" width="220" alt="额度适中时的宠物小组件"> | <img src="images/low.png" width="220" alt="额度紧张时的宠物小组件"> |

## 系统要求

- macOS 14 Sonoma 或更高版本
- 已在本机使用过 Claude Code 或 Codex，以便产生可读取的本地日志
- 从源码构建完整 App 时需要 Xcode

## 安装

目前请从源码构建。克隆仓库后打开工程：

```bash
git clone https://github.com/Nova0313/TokenViewer.git
cd TokenViewer
open TokenViewer.xcodeproj
```

在 Xcode 中：

1. 为 `TokenViewer` 和 `TokenViewerWidget` 两个 Target 选择你自己的开发团队（`DEVELOPMENT_TEAM` 已在 `project.yml` 中留空，贡献者需自行设置）。
2. 确认两个 Target 使用同一个 App Group；默认配置为 `group.com.tokenviewer.shared`。
3. 选择 `TokenViewer` Scheme，点击 Run。

> 语言 / Language: [简体中文](README.md) | [English](README_EN.md)

App 启动后只显示在菜单栏，不占用 Dock。

### 添加桌面小组件

1. 先启动 TokenViewer 并刷新一次额度。
2. 在桌面右键，选择“编辑小组件”。
3. 搜索 `TokenViewer`，选择需要的尺寸或额度宠物。
4. 右键已添加的小组件，可配置服务、额度周期和显示风格。

## 数据来源与限制

TokenViewer 当前读取以下目录中的 JSONL 日志：

- Codex：`~/.codex/sessions`
- Claude Code：`~/.claude`

Codex 日志通常包含短期和长期额度窗口。Claude Code 并不总是在本地日志中保存订阅额度；没有兼容数据时，TokenViewer 会显示“不可用”，不会根据 token 消耗量推算额度。

读取结果取决于上游日志格式，Claude Code 或 Codex 更新后可能需要同步适配。移除服务绑定只会删除 TokenViewer 自己的本地配置，不会修改原应用或其日志。

## 本地开发

直接运行菜单栏版本：

```bash
swift run TokenViewer
```

构建不含 WidgetKit 扩展的独立菜单栏 App：

```bash
./scripts/build-app.sh
open dist/TokenViewer.app
```

运行测试：

```bash
swift test
```

项目使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理 Xcode 工程。修改 `project.yml` 后可重新生成：

```bash
brew install xcodegen
./scripts/generate-xcode-project.sh
```

仓库已包含生成好的 `TokenViewer.xcodeproj`，仅构建项目时无需安装 XcodeGen。

## 隐私

额度解析完全在本机进行。TokenViewer 不需要登录 Claude 或 OpenAI 账号，也不会上传本地日志或账号信息。桌面小组件所需的额度快照通过 App Group 在主应用与 WidgetKit 扩展之间共享。

## 参与贡献

欢迎提交 Issue 和 Pull Request。报告额度解析问题时，请勿上传包含提示词、账号信息或其他敏感内容的完整日志；建议只提供已脱敏的额度字段和日志结构。
