<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="WhyText icon">
</p>

<h1 align="center">WhyText</h1>

<p align="center">
  <strong>Select text anywhere on macOS, press a shortcut, and get a translation or explanation from the LLM of your choice.</strong>
</p>

<p align="center">
  <a href="https://github.com/lima1217/whytext/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/lima1217/whytext?label=release"></a>
  <a href="https://github.com/lima1217/whytext/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/lima1217/whytext/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center">
  <b>English</b> · <a href="README.zh-CN.md">简体中文</a>
</p>

---

WhyText is a lightweight menu bar app for macOS. It reads the text you have selected in any application, sends it to an OpenAI-compatible provider you configure (for example DeepSeek or OpenAI), and streams the result into a floating panel next to your cursor. Your API key never leaves the macOS Keychain, and nothing is sent anywhere except the provider you choose.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Privacy](#privacy)
- [Building from Source](#building-from-source)
- [Project Structure](#project-structure)
- [Contributing](#contributing)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

### Input

- **Global hotkey** (default `⌥ Space`) translates the current selection in any app.
- **Selection bubble** (optional) appears next to selected text with *Translate* and *Explain* actions.
- **Manual input**: with nothing selected (or via **Translate Typed Text…** in the menu bar), a text box opens so you can type or paste.
- **Screenshot translation**: drag out a screen region; its text is recognized on-device (OCR) and translated. Can have its own shortcut.

### Translation

- **Automatic direction**: text in your primary language goes to your second language, everything else to your primary language. Override it in Settings or per result.
- **Translate or explain**: switch modes, view the source text, and ask follow-up questions in the result panel.
- **Streaming output** when the provider supports it, with automatic fallback to non-streaming.
- **Long input**: translations over 4,000 characters are split into chunks and requested in parallel (up to 3 at once), displayed in order.
- **Recent results** can be reopened from the menu bar. Identical requests reuse the stored result instead of calling the provider again.
- **Reading memory** keeps every finished lookup with where it came from (app, window title, web page or document) and, in apps that expose it, the sentence around the selection. Looking up the same word again shows how many times you have; export everything as a folder of plain Markdown files.
- **Glossary**: star a translated word to keep its rendering. Later translations that contain the word use it, and you can edit or remove entries in Settings.

### Customization

- **Multiple provider profiles**, each with its own Base URL, model, and API format (`Chat Completions` or `Responses`).
- **Prompt templates** for translate and explain, with `{{text}}` (source) and `{{target}}` (target language) placeholders.
- **Interface languages**: Simplified Chinese, Traditional Chinese, English, Japanese, Korean, or follow the system.
- **Panel behavior**: opens beside the selection without covering it, and the app you're reading keeps its focus. Closes on an outside click, or pin it to keep it open. One-click copy as rich text with a plain-text fallback.
- **Launch at login** and **one-click in-app updates**.

## Installation

**Requirements:** macOS 13 Ventura or later.

1. Download the latest `WhyText-<version>-mac.zip` from [Releases](https://github.com/lima1217/whytext/releases/latest).
2. Unzip it and move `WhyText.app` to `/Applications`.
3. Open it. WhyText is not notarized by Apple, so macOS blocks it on first launch:

   | macOS version | How to allow it |
   | --- | --- |
   | 15 Sequoia and later | Open the app once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. |
   | 13 Ventura / 14 Sonoma | In Finder, right-click `WhyText.app` → **Open**, then click **Open**. |
   | Any | Run the command below in Terminal, then open the app normally. |

   ```bash
   xattr -dr com.apple.quarantine /Applications/WhyText.app
   ```

### Updating

From 0.4.1 on, when a new version is available the menu bar shows **Update to x.x.x…**. One click downloads and verifies the update, then relaunches into the new version. Settings and API keys are kept.

- WhyText only installs builds signed with the same certificate as the running app.
- If it can't update in place (for example, the app is not in a writable folder), it opens the download page so you can replace the app manually.
- Versions 0.4.0 and earlier need one manual update.
- If selected text stops being read after an update, remove WhyText from **System Settings → Privacy & Security → Accessibility** and add it again.

## Getting Started

1. Open **WhyText → Settings…** from the menu bar.
2. Under **Shortcuts**, set your global hotkey.
3. Under **Permissions**, grant **Accessibility** permission. WhyText needs it to read selected text.
4. Under **Providers**, add a provider. For example, DeepSeek:

   | Field | Value |
   | --- | --- |
   | Base URL | `https://api.deepseek.com` |
   | Model | `deepseek-chat` |
   | API Format | `Chat Completions` (default) |
   | API Key | your key (saved to Keychain) |

   Use the built-in connectivity check to confirm the Base URL, key, and model work.
5. Select text in any app and press your hotkey.

## Configuration

Settings are grouped into pages in the sidebar of the Settings window:

| Page | What you can configure |
| --- | --- |
| General | Interface language, launch at login, and recent-results history (turn off or clear). |
| Shortcuts | Hotkeys for translating the selection and for screenshot translation; the optional selection bubble. |
| Translation Direction | Primary and second language for automatic direction; result panel text size. |
| Providers | Provider profiles (Base URL, model, API format, API key) and a connectivity check. |
| Prompts | Translate and explain templates. Each must contain `{{text}}`. The hotkey runs *translate*; the bubble's question-mark action runs *explain*. |
| Reading Memory | Turn recording on or off, edit or remove glossary entries, export to a Markdown folder, or clear it. |
| Permissions | Accessibility status and selection-reading diagnostics. |
| Updates | Daily update checks and one-click install. |

## Privacy

| Data | Storage / behavior |
| --- | --- |
| API keys | macOS Keychain. |
| Other settings | `UserDefaults`. |
| Selected text | Sent only to the provider you configured. |
| Glossary | Starred terms and renderings in `~/Library/Application Support/<bundle ID>/memory/glossary.json`. When a translation contains a starred term, that term and its rendering are sent to your provider with the request. |
| Screenshots | Require Screen Recording permission. Used only for on-device text recognition and deleted immediately; only the recognized text is sent to your provider. |
| Recent results | Up to 50 entries in `~/Library/Application Support/<bundle ID>/recent-results.json`. Can be turned off or cleared. |
| Reading memory | Every finished lookup (text, result, app, window title, page or document address, surrounding sentence) in `~/Library/Application Support/<bundle ID>/memory/lookups.jsonl`. Never sent anywhere. Can be turned off, exported, or cleared. |
| Update checks | When daily checks are on, WhyText asks the GitHub API for the latest version number once a day and sends nothing else. Updates are downloaded only when you click to install. |
| Telemetry | None. WhyText includes no third-party analytics. |

## Building from Source

**Requirements:** macOS 13+, Swift 5.10. Xcode is optional; the Command Line Tools are enough:

```bash
xcode-select --install
```

### Xcode

Open `Package.swift` in Xcode and click **Run**.

### Command line

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift build --cache-path /tmp/swiftpm-cache

CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift run WhyTextCoreSmokeTests --cache-path /tmp/swiftpm-cache

.build/debug/WhyText
```

### App bundle

```bash
./scripts/build-app.sh
open ./dist/WhyText.app
```

The build script signs with a `Developer ID Application` or `Apple Development` certificate from your keychain when one is available. Otherwise it creates and reuses a local self-signed `WhyText Local Code Signing` identity, so Accessibility permission stays tied to a stable certificate instead of an ad-hoc signature that changes on every build.

## Project Structure

```text
Sources/
├── WhyText/                     # The app
│   ├── WhyTextApp.swift         # Entry point (MenuBarExtra)
│   ├── AppModel.swift           # Top-level state orchestration
│   ├── Models/                  # Panel, connectivity, and translation preflight models
│   ├── Services/                # Selection, translation session, hotkeys, panels, LLM client
│   ├── Stores/                  # Settings storage
│   ├── UI/                      # Settings pages and panel views
│   └── Utils/                   # Helpers
├── WhyTextCore/                 # Pure, testable logic (chunking, endpoints, stream parsing, selection)
│   └── Localization/            # Interface strings, keyed by the Simplified Chinese text
└── WhyTextCoreSmokeTests/       # Smoke tests that run without Xcode
scripts/build-app.sh             # Builds and signs the .app bundle
VERSION                          # Short version and build number, read by the build script
.github/workflows/ci.yml         # CI: build and smoke tests
```

## Contributing

Issues and pull requests are welcome. Before opening a pull request:

1. Make sure the project builds and `WhyTextCoreSmokeTests` passes (CI runs both).
2. For UI changes, walk through the relevant items in [`docs/manual-checklist.md`](docs/manual-checklist.md).
3. **Localization:** wrap new interface text in `L10n.t("简体中文 text")`, or `L10n.f("…%@…", value)` for formatted strings, and add the same key to all four tables in `Sources/WhyTextCore/Localization/`. Missing or unused keys fail the smoke tests.

## Troubleshooting

<details>
<summary><b>"No selected text detected"</b></summary>

- Make sure WhyText has Accessibility permission, and run the diagnostics under **Settings → Permissions**.
- Some apps don't expose their selection through Accessibility. Try another app to confirm.
- After an update, remove WhyText from the Accessibility list and add it again.

</details>

<details>
<summary><b>No streaming output</b></summary>

Streaming depends on whether your provider and API format support SSE. WhyText falls back to non-streaming automatically.

</details>

<details>
<summary><b>"Invalid API key"</b></summary>

Check that the key is correct, has not expired, and has access to the configured model.

</details>

## License

WhyText is released under the [MIT License](LICENSE).
