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
- Confirm the copy button copies rich text (bold/headings/lists) into Notes/Pages, with plain-text fallback.
- Translate English text and confirm the title shows → 简体中文; translate Chinese text and confirm → English.
- Pick another language from the → menu and confirm it retranslates; change 母语 / 第二语言 in 通用 and confirm the direction follows.
- Switch 翻译 / 解释 in the panel and confirm it reruns on the same selection.
- Expand 原文 and confirm the panel grows; collapse it again.
- Ask a follow-up question (Return sends, Esc closes the panel); confirm the answer uses the earlier result as context and copy includes it.
- Click outside the panel and confirm it closes; pin it, click outside, and confirm it stays open.
- Translate the same text twice; the second time shows 来自最近记录 instantly, and 重新生成 requests again.
- Open 最近 in the menu bar, pick an entry, and confirm the panel shows it and accepts a follow-up. Clear it and confirm the menu disappears.
- Turn off 保存最近的翻译和解释 and confirm records are cleared and repeated text is requested again.
- With a small max input length, translate a multi-paragraph text and confirm chunks appear in order.
- With nothing selected, press the shortcut: the panel shows a text box with the cursor in it. Type, ⌘↩ translates, 解释 explains, Esc closes.
- Without Accessibility permission, the text box shows the 未授权 hint and 授权 opens System Settings.
- Use 截图翻译… from the menu bar (and the shortcut, if set): the first time, the Screen Recording prompt appears and the panel offers 打开系统设置. After granting and relaunching, drag a region with text and confirm it's recognized and translated; Esc cancels without opening the panel.
- In 通用 → 界面语言, switch through 繁體中文 / English / 日本語 / 한국어 with Settings open: every tab, the window title, the menu bar menu, and the panel follow immediately. 跟随系统 matches the macOS language (English if unsupported).
- Set a shortcut to ⌘Space: a yellow note says macOS uses it. Set 截图翻译 to the same combination as the main shortcut: a red note says they're the same, and the menu bar shows 快捷键需要处理.
- One-click update (needs an older installed version and a newer release): 更新到 x.x.x… in the menu bar (or 立即更新 in Settings) shows download progress, then WhyText quits and reopens as the new version from the same location. A copy run from a read-only folder or Downloads (translocated) offers the download page instead.
- In 通用 → 更新, click 立即检查 and confirm it reports 已是最新版本 (or the newer version with 前往下载 when one exists).
- In the packaged app, toggle 登录时自动启动 and confirm WhyText appears in System Settings → General → Login Items.

## Failure Cases

- Remove API Key and trigger translation. The panel should show a clear API Key error.
- Use an invalid model and run 服务商 connectivity test. The Model row should show unavailable with a useful message.
- Revoke Accessibility permission and trigger translation. The app should show the no-permission or no-selection path without crashing.

## Packaging

- Build with `./scripts/build-app.sh`.
- Verify `codesign --verify --deep --strict --verbose=2 dist/WhyText.app`.
- Replace `/Applications/WhyText.app` only after the checks above pass.
