# WhyText

[中文](README.zh-CN.md) | [English](README.en.md)

WhyText is a macOS menu bar translation utility: select text anywhere and translate it with a global shortcut.

## Features

- Lightweight menu bar app
- Global hotkey trigger (default: `⌥ + Space`)
- Optional selection bubble mode (click bubble to translate)
- Streaming output when supported by your provider
- Automatic chunking or truncation for long input
- One-click copy for translation results (including plain-text copy)
- Custom prompt template with `{{text}}` placeholder
- Multiple provider profiles (Base URL / Model / API Mode)
- API keys stored in macOS Keychain

## Requirements

- macOS 13+
- Swift 5.10 (Command Line Tools are enough)

Install Command Line Tools if needed:

```bash
xcode-select --install
```

## Quick Start

1. Build and launch the app (see "Run and Build" below).
2. Open menu bar `WhyText -> Settings...`.
3. Set your global hotkey in the General tab.
4. Grant Accessibility permission to WhyText (required to read selected text).
5. Configure your provider in Providers (DeepSeek example):
   - Base URL: `https://api.deepseek.com`
   - Model: `deepseek-chat`
   - API Mode: `Chat Completions` (default)
   - Enter API key (saved in Keychain)
6. Select text in any app and press your shortcut to translate.

## Run and Build

### Option A: Xcode (recommended)

Open `Package.swift` in Xcode and click Run.

### Option B: Command line

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift build --cache-path /tmp/swiftpm-cache

.build/debug/WhyText
```

### Option C: Build a double-clickable .app (without Xcode)

```bash
./scripts/build-app.sh
open ./dist/WhyText.app
```

The build script signs with a `Developer ID Application` or `Apple Development` certificate from your keychain when one is available. If none exists, it creates and reuses a local self-signed `WhyText Local Code Signing` identity. This gives macOS Accessibility permission a stable certificate identity instead of an ad-hoc signature that changes on every build.

## Configuration

- Prompt template: edit it in Prompts; must include `{{text}}`.
- Streaming: toggle in General.
- Long input: configure max length and split/truncate behavior.
- Provider connectivity check: verify Base URL / API key / model in Settings.

## Data and Privacy

- API keys: stored in macOS Keychain.
- Other settings: stored in `UserDefaults`.
- No built-in third-party telemetry.

## Project Structure

```text
Sources/WhyText/
  WhyTextApp.swift          # App entry (MenuBarExtra)
  AppModel.swift            # Main state and workflow
  Services/                 # Selection, hotkey, panel, LLM request logic
  Stores/                   # Settings storage
  UI/                       # Settings pages and panel views
  Utils/                    # Utility helpers
scripts/build-app.sh        # Build script for .app bundle
```

## FAQ

- "No selected text detected"
  - Ensure Accessibility permission is granted.
  - Some apps do not expose selection via Accessibility; test with another app.

- No streaming output
  - Depends on provider and API mode SSE support. The app falls back to non-streaming automatically.

- API key invalid
  - Verify key value, expiration, and model access permissions.

## License

No license file yet (defaults to all rights reserved). Add a `LICENSE` file if you plan to open source it.
