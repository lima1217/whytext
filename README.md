# WhyText

一个自用的 macOS 菜单栏小工具：

- 选中文本后按全局快捷键弹出浮窗
- 浮窗只做一件事：翻译
- 翻译走 DeepSeek 官方 API（在线）
- 本地保存历史记录，API Key 本地保存在 Keychain

## 使用方式

1. 首次运行后，先到「WhyText → 设置…」
2. 在「通用」里设置全局快捷键
3. 在「辅助功能权限」里打开系统设置并授权 WhyText（否则无法读取选中文本）
4. 在「Provider」里配置 DeepSeek：
   - `Base URL`：`https://api.deepseek.com`
   - `Model`：`deepseek-chat`（可改）
   - 填写 API Key（保存在本机 Keychain）
5. 在任意 App 里选中文本，按你设置的快捷键呼出浮窗 → 点「翻译」

默认在「通用」里开启“选中文本后显示翻译浮点”：选中后先出现一个浮点按钮，点击才会弹出窗口并翻译；不点击则不翻译。

浮窗支持：

- 一键复制翻译结果
- 可调整窗口大小（会记住上次尺寸）

## 提示词

「提示词」里可以自定义翻译提示词模板：

- 用 `{{text}}` 代表当前选中的文本

## 历史记录

- 默认保存在 `~/Library/Application Support/WhyText/history.json`
- 在「历史」页可以清空

## 运行/构建

> 你不需要安装 Xcode。
> 
> 只要安装 Apple Command Line Tools 即可（如果还没装：`xcode-select --install`）。

### 方式 A：Xcode（推荐）

- 直接用 Xcode 打开 `Package.swift`，点击 Run。

### 方式 B：命令行

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift build --cache-path /tmp/swiftpm-cache
```

构建产物会在 `.build/` 目录下生成可执行文件（例如 `.build/debug/WhyText`）。

### 方式 C：生成可双击运行的 .app（无 Xcode）

```bash
./scripts/build-app.sh
open ./dist/WhyText.app
```

这种方式更适合测试辅助功能权限（系统设置里会把它当成一个 App）。

## 已知限制

- 不是所有应用都能通过辅助功能拿到选中文本；如果遇到「没有检测到选中文本」，可以换个 App 试试。
- 流式输出依赖 Provider 是否支持 SSE；不支持时会自动退回非流式。
- 超长文本会按设置进行“分段”或“截断”。
