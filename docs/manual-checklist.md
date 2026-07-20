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
- Toggle 选中文本后显示操作气泡 and confirm it persists after reopening settings.
- In 提示词, edit both 翻译提示词 and 解释提示词, use 插入 `{{text}}`, and 恢复默认. Reopen settings and confirm both templates persist.
- In 服务商, add a provider from a template, switch provider, test connectivity, and remove it.

## Translation / Explain Flow

- Select text in a native text editor and trigger the shortcut (translate).
- Select text in a browser and trigger the shortcut.
- Select text and click the bubble’s translate action; confirm the panel title reflects 翻译.
- Select text and click the bubble’s explain (question-mark) action; confirm the panel title reflects 解释 and the explain prompt is used.
- Confirm the bubble appears near the selection when the app provides selection bounds, and still appears near the mouse as fallback.
- Confirm the result panel has rounded lower corners.
- Confirm the copy button copies plain text.
- Confirm clicking the result area copies plain text.

## Failure Cases

- Remove API Key and trigger translation. The panel should show a clear API Key error.
- Use an invalid model and run 服务商 connectivity test. The Model row should show unavailable with a useful message.
- Revoke Accessibility permission and trigger translation. The app should show the no-permission or no-selection path without crashing.

## Packaging

- Build with `./scripts/build-app.sh`.
- Verify `codesign --verify --deep --strict --verbose=2 dist/WhyText.app`.
- Replace `/Applications/WhyText.app` only after the checks above pass.
