<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="WhyText 图标">
</p>

<h1 align="center">WhyText</h1>

<p align="center">
  <strong>在 macOS 任意位置选中文本，按下快捷键，即可用你选择的大模型翻译或解释。</strong>
</p>

<p align="center">
  <a href="https://github.com/lima1217/whytext/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/lima1217/whytext?label=release"></a>
  <a href="https://github.com/lima1217/whytext/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/lima1217/whytext/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="平台" src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b>
</p>

---

WhyText 是一款轻量的 macOS 菜单栏应用。它读取你在任意应用中选中的文本，发送给你配置的 OpenAI 兼容服务商（如 DeepSeek、OpenAI），并把结果以流式方式显示在光标旁的浮窗中。API Key 只保存在 macOS 钥匙串里，数据只会发送给你自己选择的服务商。

## 目录

- [功能特性](#功能特性)
- [安装](#安装)
- [快速开始](#快速开始)
- [设置说明](#设置说明)
- [数据与隐私](#数据与隐私)
- [从源码构建](#从源码构建)
- [项目结构](#项目结构)
- [参与贡献](#参与贡献)
- [常见问题](#常见问题)
- [许可证](#许可证)

## 功能特性

### 输入方式

- **全局快捷键**（默认 `⌥ Space`）：在任意应用中翻译当前选中的文本。
- **操作气泡**（可选）：选中文本后在旁边显示「翻译」「解释」按钮。
- **手动输入**：没有选中文字时（或通过菜单栏「输入文字翻译…」）弹出输入框，可直接输入或粘贴。
- **截图翻译**：框选屏幕区域，在本机识别文字（OCR）后翻译，可设置单独的快捷键。

### 翻译

- **自动判断方向**：母语译成第二语言，其他语言译成母语；可在设置或结果窗口中修改。
- **翻译与解释**：在结果窗口中切换模式、查看原文、继续追问。
- **流式输出**：服务商支持时实时显示，不支持时自动回退到非流式。
- **长文本**：超过 4000 字的翻译会自动分段并行请求（最多 3 段同时进行），按顺序显示。
- **最近记录**：可从菜单栏找回之前的结果；相同请求直接复用，不重复调用服务商。

### 个性化

- **多服务商配置**：每个配置可单独设置 Base URL、模型和 API 格式（`Chat Completions` 或 `Responses`）。
- **提示词模板**：翻译、解释分别可自定义，支持 `{{text}}`（原文）和 `{{target}}`（目标语言）占位符。
- **界面语言**：简体中文、繁體中文、English、日本語、한국어，或跟随系统。
- **浮窗行为**：点击窗口外自动关闭，用图钉固定后保持常驻；结果可一键复制为富文本（含纯文本回退）。
- **登录时自动启动**，以及**应用内一键更新**。

## 安装

**系统要求：** macOS 13 Ventura 及以上。

1. 从 [Releases](https://github.com/lima1217/whytext/releases/latest) 下载最新的 `WhyText-<版本>-mac.zip`。
2. 解压后把 `WhyText.app` 拖进「应用程序」。
3. 打开应用。WhyText 未经 Apple 公证，首次打开时会被 macOS 拦截：

   | macOS 版本 | 放行方式 |
   | --- | --- |
   | 15 Sequoia 及以上 | 先打开一次，然后进入 **系统设置 → 隐私与安全性**，在页面下方点击 **仍要打开**。 |
   | 13 Ventura / 14 Sonoma | 在 Finder 中右键 `WhyText.app` → **打开**，再点击 **打开**。 |
   | 任意版本 | 在终端执行下面的命令，然后正常打开。 |

   ```bash
   xattr -dr com.apple.quarantine /Applications/WhyText.app
   ```

### 更新

从 0.4.1 起，有新版本时菜单栏会出现 **更新到 x.x.x…**。点击后会自动下载、校验并重启到新版本，设置和 API Key 都会保留。

- WhyText 只会安装与当前应用使用同一证书签名的版本。
- 如果无法原地更新（例如应用不在可写的文件夹中），会改为打开下载页，由你手动替换。
- 0.4.0 及更早版本需要手动更新一次。
- 如果更新后读取不到选中文本，请在 **系统设置 → 隐私与安全性 → 辅助功能** 中移除 WhyText 后重新添加。

## 快速开始

1. 点击菜单栏 **WhyText → 设置…**。
2. 在 **快捷键** 页设置全局快捷键。
3. 在 **权限** 页授予 **辅助功能** 权限，WhyText 需要它来读取选中的文本。
4. 在 **服务商** 页添加服务商，以 DeepSeek 为例：

   | 字段 | 值 |
   | --- | --- |
   | Base URL | `https://api.deepseek.com` |
   | Model | `deepseek-chat` |
   | API 格式 | `Chat Completions`（默认） |
   | API Key | 你的密钥（保存到钥匙串） |

   可以用内置的连接测试确认 Base URL、API Key 和模型是否可用。
5. 在任意应用中选中文本，按下快捷键即可。

## 设置说明

设置窗口左侧边栏按页面分组：

| 页面 | 可配置内容 |
| --- | --- |
| 通用 | 界面语言、登录时自动启动、最近记录（可关闭或清除）。 |
| 快捷键 | 翻译选中文本、截图翻译的快捷键；是否显示操作气泡。 |
| 翻译方向 | 自动判断方向所用的母语与第二语言；结果窗口文字大小。 |
| 服务商 | 服务商配置（Base URL、模型、API 格式、API Key）及连接测试。 |
| 提示词 | 翻译、解释模板，必须包含 `{{text}}`。快捷键执行「翻译」，气泡上的问号执行「解释」。 |
| 权限 | 辅助功能授权状态与选区读取诊断。 |
| 更新 | 每天自动检查更新与一键安装。 |

## 数据与隐私

| 数据 | 存储方式 / 行为 |
| --- | --- |
| API Key | 保存在 macOS 钥匙串。 |
| 其他设置 | 保存在 `UserDefaults`。 |
| 选中的文本 | 只发送给你配置的服务商。 |
| 截图 | 需要「屏幕录制」权限；仅用于在本机识别文字，识别后立即删除，只有识别出的文字会发给服务商。 |
| 最近记录 | 最多 50 条，保存在 `~/Library/Application Support/<Bundle ID>/recent-results.json`，可关闭或清除。 |
| 检查更新 | 开启每天自动检查时，每天向 GitHub API 查询一次最新版本号，不发送其他任何信息；只有点击更新后才会下载安装包。 |
| 数据上报 | 无。WhyText 不包含任何第三方统计。 |

## 从源码构建

**环境要求：** macOS 13+、Swift 5.10。Xcode 不是必需的，安装命令行工具即可：

```bash
xcode-select --install
```

### 使用 Xcode

用 Xcode 打开 `Package.swift`，点击 **Run**。

### 使用命令行

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift build --cache-path /tmp/swiftpm-cache

CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift run WhyTextCoreSmokeTests --cache-path /tmp/swiftpm-cache

.build/debug/WhyText
```

### 打包 .app

```bash
./scripts/build-app.sh
open ./dist/WhyText.app
```

打包脚本会优先使用钥匙串中的 `Developer ID Application` 或 `Apple Development` 证书签名；没有可用证书时，会自动创建并复用本机自签名证书 `WhyText Local Code Signing`。这样辅助功能权限会绑定到稳定的证书身份，而不是每次构建都会变化的 ad-hoc 签名。

## 项目结构

```text
Sources/
├── WhyText/                     # 应用本体
│   ├── WhyTextApp.swift         # 入口（MenuBarExtra）
│   ├── AppModel.swift           # 顶层状态编排
│   ├── Models/                  # 浮窗、连通性、翻译预检模型
│   ├── Services/                # 选区、翻译会话、快捷键、浮窗、LLM 客户端
│   ├── Stores/                  # 设置存储
│   ├── UI/                      # 设置页与浮窗视图
│   └── Utils/                   # 工具函数
├── WhyTextCore/                 # 可测试的纯逻辑（分段、端点、流解析、选区）
│   └── Localization/            # 界面文字，以简体中文原文为键
└── WhyTextCoreSmokeTests/       # 无需 Xcode 即可运行的冒烟测试
scripts/build-app.sh             # 构建并签名 .app
VERSION                          # 短版本号与 build 号，由打包脚本读取
.github/workflows/ci.yml         # CI：构建 + 冒烟测试
```

## 参与贡献

欢迎提交 Issue 和 Pull Request。提交 PR 前请确认：

1. 项目可以正常构建，且 `WhyTextCoreSmokeTests` 通过（CI 会运行这两项）。
2. 涉及界面的改动，请按 [`docs/manual-checklist.md`](docs/manual-checklist.md) 中的相关项手动验证。
3. **本地化**：新增界面文字用 `L10n.t("简体中文原文")`（带参数用 `L10n.f("…%@…", 值)`），并在 `Sources/WhyTextCore/Localization/` 的四个对照表中加入同一个键。漏加或多余的键都会导致冒烟测试失败。

## 常见问题

<details>
<summary><b>提示「未读取到选中文本」</b></summary>

- 确认已授予辅助功能权限，并在 **设置 → 权限** 中运行诊断。
- 部分应用不支持通过辅助功能读取选区，可换一个应用测试。
- 更新后出现此问题，请在辅助功能列表中移除 WhyText 后重新添加。

</details>

<details>
<summary><b>没有流式输出</b></summary>

取决于服务商和 API 格式是否支持 SSE，WhyText 会自动回退到非流式。

</details>

<details>
<summary><b>提示 API Key 无效</b></summary>

检查 Key 是否正确、是否过期，以及是否有所配置模型的访问权限。

</details>

## 许可证

WhyText 基于 [MIT 许可证](LICENSE) 发布。
