# TokenPulse Agent Guide

## Provider icons

Provider icon assets live in `TokenPulse/Resources/ProviderIcons.xcassets`. Keep their provenance and license in `TokenPulse/Resources/ProviderIconNotices.txt`.

| Providers | Source |
| --- | --- |
| Claude, Codex/OpenAI, OpenCode, Z.ai, MiniMax, SuperGrok | [Lobe Icons](https://github.com/lobehub/lobe-icons), imported through `qunqin24/Pulse` commit `8d7fd60454ce383dd0a136a30790c1e277f8069b`, under the MIT License. |
| Qoder, DeepSeek | [Lobe Icons](https://github.com/lobehub/lobe-icons) commit `a94750e3f5f8fc33757b839d85030e742284e43a`, under the MIT License. Their shapes were checked against the providers' official favicons. |
| Kimi Code | [Lobe Icons](https://github.com/lobehub/lobe-icons) commit `2e76c48721e91b9aaa40803a0fa2eb8aca7399c4`, file `packages/static-svg/icons/kimi.svg`, under the MIT License. |

When adding or replacing a provider icon:

1. Prefer the provider's official repository asset. Otherwise use the existing Lobe Icons source.
2. Pin the source commit and record the repository, asset path, copyright, and license in `ProviderIconNotices.txt`.
3. Package the SVG as an Xcode image set with vector preservation and template rendering. Replace `currentColor` with black and keep explicit dimensions so SwiftUI tinting works consistently.
4. Map the image-set name in `TokenPulse/UI/ProviderIcon.swift`.
5. Run an unsigned `TokenPulse` target build; completion means the asset catalog compiles for the app, widgets, and Watch targets.
