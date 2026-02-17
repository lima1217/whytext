# WhyText

WhyText 是一个 macOS 菜单栏翻译工具：选中文本后，用快捷键一键翻译。

## 功能

- 菜单栏常驻，轻量使用
- 全局快捷键触发（默认 `⌥ + Space`）
- 可选「选中文本后显示浮点」模式，点击浮点再翻译
- 支持流式输出（Provider 支持时）
- 长文本自动分段或截断
- 结果一键复制（支持纯文本复制）
- 自定义翻译提示词模板（`{{text}}` 占位符）
- 多 Provider 配置（Base URL / Model / API Mode）
- API Key 保存在 macOS Keychain
- 历史记录本地存储，可随时清空

## 系统要求

- macOS 13+
- Swift 5.10（Command Line Tools 即可）

安装命令行工具（如未安装）：

```bash
xcode-select --install
```

## 快速开始

1. 构建并启动应用（见下方“运行与构建”）。
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

.build/debug/WhyText
```

### 方式 C：生成 .app（无 Xcode）

```bash
./scripts/build-app.sh
open ./dist/WhyText.app
```

## 配置说明

- 翻译提示词：在「提示词」页编辑模板，必须包含 `{{text}}`。
- 流式输出：在「通用」里可开关。
- 长文本策略：可配置最大输入长度与分段/截断策略。
- Provider 连接测试：在设置中可快速验证 Base URL / API Key / Model 是否可用。

## 数据与隐私

- API Key：存储在 macOS Keychain。
- 其他设置：保存在 `UserDefaults`。
- 历史记录：默认保存在 `~/Library/Application Support/WhyText/history.json`。
- WhyText 不内置第三方数据上报逻辑。

## 项目结构

```text
Sources/WhyText/
  WhyTextApp.swift          # 应用入口（MenuBarExtra）
  AppModel.swift            # 主状态与业务流程
  Services/                 # 选区读取、快捷键、浮窗、LLM 请求等
  Stores/                   # 设置与历史记录
  UI/                       # 各设置页与浮窗视图
  Utils/                    # 工具函数
scripts/build-app.sh        # 打包 .app 脚本
```

## 常见问题

- 提示“未读取到选中文本”
  - 检查是否已授予辅助功能权限。
  - 某些应用不支持通过辅助功能读取选区，可换应用测试。

- 没有流式输出
  - 取决于 Provider 和接口模式是否支持 SSE，应用会自动回退到非流式。

- 提示 API Key 无效
  - 检查 Key 是否正确、是否过期、是否有模型访问权限。

## License

暂未指定（All rights reserved by default）。如需开源，请补充 `LICENSE` 文件。
