# TokenViewer

<p align="center">
  <img src="images/ui.png" width="160" alt="TokenViewer icon">
</p>

<p align="center">
  Native macOS menu bar app and desktop widget to view quota usage for AI coding tools.
</p>

> TokenViewer reads local logs or queries APIs directly. It does not upload logs, quotas, or account information.

> Language: [简体中文](README.md) | [English](README_EN.md)

## Features

### Local Services

- Auto-discovers locally installed Claude Code and Codex (checks `.claude` / `.codex` data directories, `/Applications/Claude.app` / `/Applications/Codex.app`, and CLI tools in Homebrew or user bin directories)
- Reads the `rate_limits` field from Codex session logs (`~/.codex/sessions/**/*.jsonl`) to show remaining percentage and reset time
- Attempts to read compatible quota fields from Claude Code local logs; shows "Unavailable" when not provided (does not estimate quota from token consumption)
- Supports manually importing a data directory path in Settings when auto-detection fails

### API Configuration

Inspired by [CC Switch](https://github.com/farion1231/cc-switch) — fill in an API Key to pull quota usage.

**Preset templates:**

| Template | Description |
| --- | --- |
| Custom | Fully custom URL, Key, protocol format, and quota endpoint path |
| Generic | Works with most OpenAI-compatible relay services |
| NewAPI | Adapts to NewAPI / One-API style relay backends |
| Auto-detect | Uses the vendor's API Key to query account balance (supports DeepSeek, Zhipu AI, MiniMax) |

- Auto-detect mode requires the official site URL; the app matches the vendor endpoint by domain
- The detected vendor name is shown in the UI
- Custom, Generic, and NewAPI templates display the extractor code for easy comparison with vendor docs
- API Keys are stored securely in the system Keychain

**Vendors and fields supported by Auto-detect:**

| Vendor | Balance field | Description |
| --- | --- | --- |
| DeepSeek | `Total Balance (Available)` | `total_balance`, current total available amount (granted + topped-up) |
| DeepSeek | `Granted Balance (Free)` | `granted_balance`, free quota granted by the platform, non-refundable, usually expires |
| DeepSeek | `Topped-up Balance (Paid)` | `topped_up_balance`, amount actually topped up by the user |
| Zhipu AI | `Short Window (5h)` / `Long Window (7d)` | Window type auto-detected from `window_minutes` |
| MiniMax | `Total Balance (Available)` | `balance`, current total available amount |
| MiniMax | `Granted Balance (Free)` | `credit_balance`, granted quota |
| MiniMax | `Topped-up Balance (Paid)` | `cash_balance`, amount actually topped up |

> Multi-currency accounts are displayed per currency, e.g. `Total Balance (CNY) (Available)`, `Total Balance (USD) (Available)`.

### UI and Interaction

- Shows the lowest remaining percentage across all available quotas in the menu bar
- Manual refresh, plus 1 / 5 / 15 / 30 / 60 minute auto-refresh
- Add, remove, reorder services, and control whether each syncs to the widget
- Configurable 1×1 and 1×2 dashboard widgets and a quota pet widget
- Click the widget to open TokenViewer directly
- Widget edit dropdown auto-detects currently available services and quota windows
- Balance fields display the amount directly (e.g. `¥9.99`); progress fields show remaining percentage
- Next refresh time is shown in "MM-DD" format (e.g. `Next 07-23`) to avoid countdown confusion

#### Desktop Widget Preview

| Dashboard widget (1×1 / 1×2) |
| :---: |
| <img src="images/screenshoot.png" width="540" alt="Dashboard widget screenshot"> |

**Quota pet states:**

| Sufficient | Moderate | Low |
| :---: | :---: | :---: |
| <img src="images/high.png" width="220" alt="Pet widget when quota is sufficient"> | <img src="images/normal.png" width="220" alt="Pet widget when quota is moderate"> | <img src="images/low.png" width="220" alt="Pet widget when quota is low"> |

## System Requirements

- macOS 14 Sonoma or later
- Local services: Claude Code or Codex must have been used locally at least once to generate readable logs
- API configuration: an API Key and related info from your vendor
- Building the full app from source requires Xcode

## Installation

### Option 1: Download a prebuilt release (recommended)

Go to the [Releases page](https://github.com/Nova0313/TokenViewer/releases), download the latest `TokenViewer-*.dmg`, mount it, and drag TokenViewer into the Applications folder.

> On first launch you may see a warning that the developer cannot be verified. Go to **System Settings → Privacy & Security** and click "Open Anyway"; or run `xattr -dr com.apple.quarantine /Applications/TokenViewer.app` in Terminal.

### Option 2: Build from source

Clone the repository and open the project:

```bash
git clone https://github.com/Nova0313/TokenViewer.git
cd TokenViewer
open TokenViewer.xcodeproj
```

In Xcode:

1. Select your own development team for both the `TokenViewer` and `TokenViewerWidget` targets (`DEVELOPMENT_TEAM` is left empty in `project.yml`; contributors need to set it themselves).
2. Confirm both targets use the same App Group; the default is `group.com.qianchen.tokenviewer.shared`.
3. Select the `TokenViewer` scheme and click Run.

You can also build a standalone menu bar app without the WidgetKit extension:

```bash
./scripts/build-app.sh
open dist/TokenViewer.app
```

After launch, the app appears only in the menu bar and does not occupy the Dock.

### Adding Desktop Widgets

1. First launch TokenViewer and refresh the quota once.
2. Right-click on the desktop and select "Edit Widgets".
3. Search for `TokenViewer` and choose the size or quota pet you need.
4. Right-click an added widget to configure service, quota period, and display style.

## Data Sources and Limitations

### Local Services

TokenViewer reads JSONL logs from the following directories:

- Codex: `~/.codex/sessions/**/*.jsonl`
- Claude Code: `~/.claude/**/*.jsonl`

The `rate_limits` field in Codex logs typically contains two windows: `primary` (short-term, 5-hour) and `secondary` (long-term, 7-day). TokenViewer reads `used_percent` to compute remaining percentage and uses the `resets_at` timestamp to show the reset time. Claude Code does not always store subscription quotas in local logs; when no compatible data is available, TokenViewer shows "Unavailable" and does not estimate quota from token consumption.

Results depend on the upstream log format. After Claude Code or Codex updates, TokenViewer may need to adapt accordingly. Removing a service binding only deletes TokenViewer's own local configuration and does not modify the original app or its logs.

### API Configuration

API configuration supports OpenAI-compatible and Anthropic-native formats. Custom, Generic, and NewAPI templates require the vendor response to match the extractor schema. Auto-detect mode matches known vendor endpoints (DeepSeek, Zhipu AI, MiniMax) by the official site domain and parses responses according to each vendor's spec.

## Local Development

Run the menu bar version directly:

```bash
swift run TokenViewer
```

Run tests:

```bash
swift test
```

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to manage the Xcode project. After modifying `project.yml`, regenerate with:

```bash
brew install xcodegen
./scripts/generate-xcode-project.sh
```

The repo already includes a generated `TokenViewer.xcodeproj`, so XcodeGen is not required just to build the project.

## Privacy

Quota parsing happens entirely on your machine. TokenViewer does not require logging in to Claude or OpenAI accounts, and does not upload local logs or account information. API Keys are stored securely in the system Keychain. Quota snapshots needed by desktop widgets are shared between the main app and the WidgetKit extension via App Group.

## Contributing

Issues and pull requests are welcome. When reporting quota parsing issues, please do not upload full logs that contain prompts, account info, or other sensitive content; prefer providing redacted quota fields and log structures.
