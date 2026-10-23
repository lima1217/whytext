# WhyText Manual Checklist

Use this checklist before replacing the local app in `/Applications`.

## Build

- Run `swift build --cache-path /tmp/swiftpm-cache`.
- Run `swift run WhyTextCoreSmokeTests --cache-path /tmp/swiftpm-cache`.
- Run `./scripts/build-app.sh` when a packaged app is needed.

## Settings Window

- Open `WhyText -> 设置…`. The window opens at about 820×600, can't shrink below 760×520, and has a transparent title bar.
- The sidebar lists 通用, 快捷键, 翻译方向, 服务商, 提示词, 权限, 更新, each with a tinted glyph tile. Selecting a row switches the pane.
- Sidebar dots: 快捷键 shows red for a blocking hotkey problem and orange when no hotkey is set or one may conflict; 服务商 shows orange with no providers; 提示词 shows red when a template is missing `{{text}}`; 权限 shows orange without Accessibility; 更新 shows blue when an update is available.
- The first group in 通用 shows the shortcut and Accessibility status; clicking each row jumps to 快捷键 / 权限.

### 快捷键

- Record a shortcut (the recorder highlights while recording), clear it, then record it again.
- Toggle 选中文本后显示操作气泡 and confirm it persists after reopening settings.
- Set a shortcut to ⌘Space: a yellow note says macOS uses it. Set 截图翻译 to the same combination as the main shortcut: a red note says they're the same, and the menu bar shows 快捷键需要处理，点此查看….

### 翻译方向

- Change 母语 / 第二语言 and confirm the panel's translation direction follows.
- Change 文字大小 and confirm the result panel text resizes.

### 服务商

- Add a provider from a template with the button next to the picker, switch provider, and remove the current one.
- Paste an API key, show/hide it, and confirm it shows 已保存到 Keychain. Clear it.
- Run 测试连通性: a spinner shows while testing, then each row reports its result.

### 提示词

- Edit both 翻译提示词 and 解释提示词, then use 恢复默认. Reopen settings and confirm both templates persist.
- Remove `{{text}}` from a template: it shows 缺少 `{{text}}`, 插入 `{{text}}` appears, and the sidebar dot turns red. Click 插入 `{{text}}`: the placeholder is added, and the badge and button disappear.

### 权限

- Without Accessibility permission, 请求授权 and 打开系统设置 work. 立即诊断 / 2秒后诊断 report results, and 复制诊断结果 copies them.

### 通用 and 更新

- In 界面语言, switch through 繁體中文 / English / 日本語 / 한국어 with Settings open: every pane, the sidebar, the window title, the menu bar menu, and the panel follow immediately. 跟随系统 matches the macOS language (English if unsupported).
- In the packaged app, toggle 登录时自动启动 and confirm WhyText appears in System Settings → General → Login Items.
- In 更新, click 立即检查 and confirm it reports 已是最新版本 (or the newer version with 立即更新 / 前往下载 when one exists).

## Selection Bubble

- Select text: the bubble is a rounded rectangle with labeled 翻译 and 解释 actions (gray outline icons) and sizes to the localized labels in every interface language.
- Confirm the bubble appears near the selection when the app provides selection bounds, and still appears near the mouse as fallback. It auto-dismisses, and hovering pauses dismissal.
- Click 翻译 and confirm the panel opens in translate mode; click 解释 and confirm explain mode and the explain prompt are used.

## Result Panel

- Select text in a native text editor and trigger the shortcut; repeat in a browser.
- The title bar shows a segmented 翻译 / 解释 control, the target language as a chip, and loading or failure as badges. Source text, result, loading skeleton, errors, and manual input sit in rounded cards.
- Translate English text and confirm the chip shows 简体中文; translate Chinese text and confirm English.
- Pick another language from the target-language chip and confirm it retranslates.
- Switch 翻译 / 解释 and confirm it reruns on the same selection.
- Expand 原文 and confirm the panel grows; collapse it again.
- Ask a follow-up question (Return sends, Esc closes the panel); confirm the answer uses the earlier result as context and copy includes it.
- Confirm the copy button copies rich text (bold/headings/lists) into Notes/Pages, with plain-text fallback.
- While a translation is loading or streaming, the copy button stays next to the pin, dimmed and unclickable; it becomes clickable once the result finishes.
- Click outside the panel and confirm it closes; pin it, click outside, and confirm it stays open.
- Translate the same text twice; the second time shows 来自最近记录，未重新请求 instantly, and 重新生成 requests again.
- Translate text longer than 4000 characters and confirm chunks appear in order.

## Other Entry Points

- With nothing selected, press the shortcut (or choose 输入文字翻译… in the menu bar): the panel shows a text box with the cursor in it. Type, ⌘↩ translates, 解释 explains, Esc closes.
- Without Accessibility permission, the text box shows the 未授权 hint and 授权 opens System Settings.
- Use 截图翻译… from the menu bar (and the shortcut, if set): the first time, the Screen Recording prompt appears and the panel offers 打开系统设置. After granting and relaunching, drag a region with text and confirm it's recognized and translated; Esc cancels without opening the panel.
- Open 最近 in the menu bar, pick an entry, and confirm the panel shows it and accepts a follow-up. Clear it and confirm the menu disappears.
- Turn off 保存最近的翻译和解释 in 通用 and confirm records are cleared and repeated text is requested again.

## Updates

- One-click update (needs an older installed version and a newer release): 更新到 x.x.x… in the menu bar (or 立即更新 in 更新) shows download progress, then WhyText quits and reopens as the new version from the same location. A copy run from a read-only folder or Downloads (translocated) offers the download page instead.

## Failure Cases

- Remove API Key and trigger translation. The panel should show a clear API Key error with 打开设置.
- Use an invalid model and run 服务商 → 测试连通性. The Model row should show unavailable with a useful message.
- Revoke Accessibility permission and trigger translation. The app should show the no-permission or no-selection path without crashing.

## Packaging

- Build with `./scripts/build-app.sh`.
- Verify `codesign --verify --deep --strict --verbose=2 dist/WhyText.app`.
- Replace `/Applications/WhyText.app` only after the checks above pass.
