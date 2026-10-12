# WhyText

[中文](README.zh-CN.md) | [English](README.en.md)

WhyText 是一个 macOS 菜单栏翻译工具：选中文本后，用快捷键一键翻译。

## 功能

- 菜单栏常驻，轻量使用
- 界面语言可选：简体中文、繁體中文、English、日本語、한국어，或跟随系统
- 全局快捷键触发（默认 `⌥ + Space`）
- 可选「选中文本后显示操作气泡」：翻译或解释
- 没有选中文字时弹出输入框，可以直接输入或粘贴
- 截图翻译：框选屏幕区域，在本机识别文字（OCR）后翻译，可设置单独的快捷键
- 自动判断翻译方向：母语译成第二语言，其他语言译成母语（可在设置和结果窗口中修改）
- 结果窗口内可切换翻译 / 解释、查看原文、继续追问
- 点击窗口外自动关闭；用图钉固定后保持常驻
- 最近记录：菜单栏「最近」找回之前的结果，相同请求直接复用，不重复计费
- 长文本分段并行请求（最多 3 段同时进行），按顺序显示
- 可设置登录时自动启动
- 支持流式输出（Provider 支持时）
- 长文本自动分段或截断
- 结果一键复制（富文本，含纯文本回退）
- 自定义翻译 / 解释提示词模板（`{{text}}` 原文、`{{target}}` 目标语言占位符）
- 多 Provider 配置（Base URL / Model / API Mode）
- API Key 保存在 macOS Keychain

## 系统要求

- macOS 13+
- Swift 5.10（Command Line Tools 即可）

安装命令行工具（如未安装）：

```bash
xcode-select --install
```

## 安装

1. 从 [Releases](https://github.com/lima1217/whytext/releases) 下载最新的 `WhyText-<版本>-mac.zip`，解压后把 `WhyText.app` 拖进「应用程序」。
2. 首次打开：WhyText 没有经过 Apple 公证，macOS 第一次会拦下它。
   - macOS 15 及以上：先双击打开一次，看到提示后进入「系统设置 → 隐私与安全性」，在页面下方点「仍要打开」。
   - macOS 13 / 14：在 Finder 里右键 `WhyText.app` → 打开 → 再点「打开」。
   - 或者在终端里执行 `xattr -dr com.apple.quarantine /Applications/WhyText.app` 后正常打开。
3. 更新：有新版本时菜单栏会出现「有新版本…」，点击打开下载页，下载后替换「应用程序」里的旧版即可，设置和 API Key 会保留。如果替换后读不到选中文本，在「系统设置 → 隐私与安全性 → 辅助功能」里把 WhyText 移除后重新添加。

## 快速开始

1. 按上方「安装」装好并打开，或自行构建（见下方“运行与构建”）。
2. 打开菜单栏 `WhyText -> 设置...`。
3. 在「通用」设置全局快捷键。
4. 在「辅助功能权限」中给 WhyText 授权（否则无法读取选中文本）。
5. 在「Providers」配置模型（以 DeepSeek 为例）：
   - Base URL: `https://api.deepseek.com`
   - Model: `deepseek-chat`
   - API Mode: `Chat Completions`（默认）
   - 填写 API Key（保存到 Keychain）
6. 在任意应用选中文本后按快捷键，即可翻译。

## 运行与构建

### 方式 A：Xcode（推荐）

直接用 Xcode 打开 `Package.swift`，点击 Run。

### 方式 B：命令行运行

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift build --cache-path /tmp/swiftpm-cache

CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift run WhyTextCoreSmokeTests --cache-path /tmp/swiftpm-cache

.build/debug/WhyText
```

### 方式 C：生成 .app（无 Xcode）

```bash
./scripts/build-app.sh
open ./dist/WhyText.app
```

打包脚本会优先使用钥匙串里的 `Developer ID Application` 或 `Apple Development` 证书签名；如果没有可用证书，会自动创建并复用 `WhyText Local Code Signing` 本机自签名证书。这样本机辅助功能权限会绑定到稳定证书身份，而不是每次构建都会变化的 ad-hoc 签名。

## 配置说明

- 翻译 / 解释提示词：在「提示词」页分别编辑模板，必须包含 `{{text}}`。快捷键默认走翻译；气泡上的问号走解释。
- 流式输出：在「通用」里可开关。
- 长文本策略：可配置最大输入长度与分段/截断策略。
- Provider 连接测试：在设置中可快速验证 Base URL / API Key / Model 是否可用。

## 数据与隐私

- API Key：存储在 macOS Keychain。
- 其他设置：保存在 `UserDefaults`。
- 截图翻译：需要「屏幕录制」权限；截图只用于在本机识别文字，识别完即删除，只有识别出的文字会发给服务商。
- 检查更新：开启「每天自动检查更新」时，WhyText 每天向 GitHub API 请求一次最新版本号，不发送任何其他信息。
- 最近记录：最多 50 条，保存在 `~/Library/Application Support/<Bundle ID>/recent-results.json`；可在设置中关闭或清除。
- WhyText 不内置第三方数据上报逻辑。

## 项目结构

```text
Sources/WhyText/
  WhyTextApp.swift          # 应用入口（MenuBarExtra）
  AppModel.swift            # 主状态编排
  Models/                   # 面板 / 连通性 / 翻译预检模型
  Services/                 # 选区、翻译会话、快捷键、浮窗、LLM 等
  Stores/                   # 设置存储
  UI/                       # 各设置页与浮窗视图
  Utils/                    # 工具函数
Sources/WhyTextCore/        # 可单测的纯逻辑（分段、端点、选区辅助）
Sources/WhyTextCore/Localization/  # 界面文字：以简体中文原文为键的各语言对照表
Sources/WhyTextCoreSmokeTests/  # Core smoke 测试（CLT 友好）
VERSION                     # 短版本号 + build 号（打包脚本读取）
scripts/build-app.sh        # 打包 .app 脚本
.github/workflows/ci.yml    # 构建 + smoke 测试
```

新增界面文字时，用 `L10n.t("简体中文原文")`（带参数用 `L10n.f("…%@…", 值)`），并在 `Sources/WhyTextCore/Localization/` 的四个对照表里加上同一个键。漏加或多余的键都会让 `WhyTextCoreSmokeTests` 失败。

## 常见问题

- 提示“未读取到选中文本”
  - 检查是否已授予辅助功能权限。
  - 某些应用不支持通过辅助功能读取选区，可换应用测试。

- 没有流式输出
  - 取决于 Provider 和接口模式是否支持 SSE，应用会自动回退到非流式。

- 提示 API Key 无效
  - 检查 Key 是否正确、是否过期、是否有模型访问权限。

## License

[MIT](LICENSE)
