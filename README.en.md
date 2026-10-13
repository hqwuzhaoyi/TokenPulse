# TokenPulse

[简体中文](README.md) · **English**

Track plan usage and balances across **78 AI providers** on your iPhone and Apple Watch.

**[Install via TestFlight](https://testflight.apple.com/join/jrHbrKmH)** · iOS 17+ · watchOS 10+

## Features

- **Multiple providers and accounts**: View plan quotas, API wallets, budgets, service credits and GPU time. Find providers quickly with search and groups.
- **Quota and balance alerts**: Configure usage thresholds, low-balance alerts and reset reminders per account.
- **Codex reset previews**: Get reset announcements and forecast alerts from [Codex Resets](https://codex-resets.com/). The section stays hidden when no active preview exists.
- **Apple Watch and widgets**: Each device can refresh independently once authorized. Supports iPhone Home Screen and Lock Screen widgets, Watch complications and Smart Stack.
- **English and Simplified Chinese**: Follows your device language, with regional date and number formatting.
- **Optional iCloud sync**: Sync account settings and quota data. Credentials are stored in Keychain; some providers require separate authorization on each device.

## Get started

1. Install the app and tap **Try Demo** to explore without an account or API key.
2. Tap **+**, find a provider, then sign in or enter an API key as prompted.
3. Enable the notifications and sync you want in **Settings**, then add widgets. On Watch, use the gear button to choose a complication account.

Background refresh, sync and widget updates are scheduled by the system, so alerts may be delayed. AI reset forecasts are not official Codex commitments.

## Providers and sign-in

Includes Claude, Codex, GitHub Copilot, Cursor, Gemini, Kiro, Kimi Code, DeepSeek, MiniMax, Zhipu, OpenCode, New API and more.

→ [Full provider directory and sign-in requirements (Chinese)](docs/providers.md)

## Development

Open the project with **Xcode 26.x / Swift 6**. Configure your own development team, App Groups, Keychain Sharing and iCloud for the targets.

```sh
git clone https://github.com/hqwuzhaoyi/TokenPulse.git
cd TokenPulse
open TokenPulse.xcodeproj
```

Run the `TokenPulse` or `TokenPulseWatch` scheme. See the [build and test guide (Chinese)](docs/development.md). Issues and pull requests are welcome.

## License and credits

Code is licensed under [Apache License 2.0](LICENSE). Third-party sources and licenses are recorded in [NOTICE](NOTICE) and the [icon notices](TokenPulse/Resources/ProviderIconNotices.txt).

Thanks to [Pulse](https://github.com/qunqin24/Pulse), [Lobe Icons](https://github.com/lobehub/lobe-icons) and [OpenAI Codex](https://github.com/openai/codex).

## Community

[LINUX DO](https://linux.do/)
