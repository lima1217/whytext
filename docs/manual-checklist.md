# WhyText Manual Checklist

Use this checklist before replacing the local app in `/Applications`.

## Build

- Run `swift build --cache-path /tmp/swiftpm-cache`.
- Run `swift run WhyTextCoreSmokeTests --cache-path /tmp/swiftpm-cache`.
- Run `./scripts/build-app.sh` when a packaged app is needed.

## Settings

- Open `WhyText -> 设置...`.
- Confirm 通用 shows shortcut and Accessibility status.
- Record a shortcut, clear it, then record it again.
- Toggle 选中文本后显示翻译按钮 and confirm it persists after reopening settings.
- In 提示词, change 目标语言, 表达风格, 保留原文段落结构, and 中英文之间自动加半角空格. Reopen settings and confirm values persist.
- Edit the prompt template, use 插入 `{{text}}`, and 恢复默认.
- In 服务商, add a provider from a template, switch provider, test connectivity, and remove it.

## Translation Flow

- Select text in a native text editor and trigger the shortcut.
- Select text in a browser and trigger the shortcut.
- Select text and click the floating bubble.
- Confirm the bubble appears near the selection when the app provides selection bounds, and still appears near the mouse as fallback.
- Confirm the translation panel has rounded lower corners.
- Confirm the copy button copies plain text.
- Confirm clicking the result area copies plain text.
- Turn off 中英文之间自动加半角空格 and confirm copied/rendered text no longer inserts extra CJK/Latin spacing.

## Failure Cases

- Remove API Key and trigger translation. The panel should show a clear API Key error.
- Use an invalid model and run 服务商 connectivity test. The Model row should show unavailable with a useful message.
- Revoke Accessibility permission and trigger translation. The app should show the no-permission or no-selection path without crashing.

## Packaging

- Build with `./scripts/build-app.sh`.
- Verify `codesign --verify --deep --strict --verbose=2 dist/WhyText.app`.
- Replace `/Applications/WhyText.app` only after the checks above pass.
