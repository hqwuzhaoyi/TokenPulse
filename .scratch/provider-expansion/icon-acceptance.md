# Provider 图标验收

2026-10-02，按用户最新要求：已实现接入票只检查图标是否存在即可验收，不再以真实账号或设备验证作为关票条件。此记录覆盖当前46个provider；不代表尚未实施的provider已接入。

检查 `ProviderIcon.swift` 的映射及实际资源：39个provider映射到37个SVG image sets（区域版本复用），7个使用5种系统SF Symbol。SVG文件均存在、可解析、有明确尺寸、无currentColor，image set开启vector preservation和template rendering。5种SF Symbol已通过本机AppKit存在性查询。相同资源已在前次c5e3382完整unsigned App/Watch/Widgets构建中编译通过；本次未改资源或运行代码，无需重复构建。

原品牌资源确实主要来自Lobe Icons（lobehub/lobe-icons），另有官方仓库资源，固定提交和许可见 `TokenPulse/Resources/ProviderIconNotices.txt`。9个provider使用通用图标：Codebuff、Neuralwatt、Aixy、Hyper、Synthetic、V2EX、xKiro、DevPass、Warp。它们通过本次“存在”验收，但不将通用图标称作官方品牌logo。

| Provider | 枚举 | 类型 | 映射 | 结果 |
| --- | --- | --- | --- | --- |
| MiniMax 国内版 | `miniMaxChina` | 品牌 SVG | `ProviderMiniMax` | 通过 |
| Claude | `claude` | 品牌 SVG | `ProviderClaude` | 通过 |
| Codex | `codex` | 品牌 SVG | `ProviderCodex` | 通过 |
| OpenCode Go | `openCodeGo` | 品牌 SVG | `ProviderOpenCode` | 通过 |
| Z.ai | `zai` | 品牌 SVG | `ProviderZai` | 通过 |
| SuperGrok | `superGrok` | 品牌 SVG | `ProviderSuperGrok` | 通过 |
| Qoder 国际版 | `qoderInternational` | 品牌 SVG | `ProviderQoder` | 通过 |
| DeepSeek | `deepSeek` | 品牌 SVG | `ProviderDeepSeek` | 通过 |
| Kimi Code 国内版 | `kimiCode` | 品牌 SVG | `ProviderKimiCode` | 通过 |
| ElevenLabs | `elevenLabs` | 品牌 SVG | `ProviderElevenLabs` | 通过 |
| Poe | `poe` | 品牌 SVG | `ProviderPoe` | 通过 |
| Vercel AI Gateway | `vercelAIGateway` | 品牌 SVG | `ProviderVercel` | 通过 |
| 智谱国内版 | `zhipu` | 品牌 SVG | `ProviderZai` | 通过 |
| MiniMax 国际版 | `miniMaxInternational` | 品牌 SVG | `ProviderMiniMax` | 通过 |
| StepFun | `stepFun` | 品牌 SVG | `ProviderStepFun` | 通过 |
| New API | `newAPI` | 品牌 SVG | `ProviderNewAPI` | 通过 |
| GitHub Copilot | `copilot` | 品牌 SVG | `ProviderCopilot` | 通过 |
| ClinePass | `clinePass` | 品牌 SVG | `ProviderClinePass` | 通过 |
| ClawRouter | `clawRouter` | 品牌 SVG | `ProviderClawRouter` | 通过 |
| Aixy | `aixy` | SF Symbol（通用） | `network` | 通过 |
| Neuralwatt | `neuralwatt` | SF Symbol（通用） | `bolt.circle` | 通过 |
| Codebuff | `codebuff` | SF Symbol（通用） | `terminal` | 通过 |
| Moonshot API 钱包 | `moonshot` | 品牌 SVG | `ProviderMoonshot` | 通过 |
| Factory | `factory` | 品牌 SVG | `ProviderFactory` | 通过 |
| Venice | `venice` | 品牌 SVG | `ProviderVenice` | 通过 |
| Hyper | `hyper` | SF Symbol（通用） | `bolt.circle` | 通过 |
| DeepInfra | `deepInfra` | 品牌 SVG | `ProviderDeepInfra` | 通过 |
| Kilo Code | `kiloCode` | 品牌 SVG | `ProviderKiloCode` | 通过 |
| Atlas Cloud | `atlasCloud` | 品牌 SVG | `ProviderAtlasCloud` | 通过 |
| Command Code | `commandCode` | 品牌 SVG | `ProviderCommandCode` | 通过 |
| Amp | `amp` | 品牌 SVG | `ProviderAmp` | 通过 |
| GitKraken AI | `gitKraken` | 品牌 SVG | `ProviderGitKraken` | 通过 |
| Hugging Face | `huggingFace` | 品牌 SVG | `ProviderHuggingFace` | 通过 |
| Synthetic | `synthetic` | SF Symbol（通用） | `puzzlepiece.extension.fill` | 通过 |
| V2EX | `v2ex` | SF Symbol（通用） | `bubble.left.and.bubble.right.fill` | 通过 |
| xKiro | `xKiro` | SF Symbol（通用） | `puzzlepiece.extension.fill` | 通过 |
| ZenMux | `zenMux` | 品牌 SVG | `ProviderZenMux` | 通过 |
| 阿里百炼 Coding Plan | `alibabaCodingPlan` | 品牌 SVG | `ProviderAlibabaCloud` | 通过 |
| Chutes | `chutes` | 品牌 SVG | `ProviderChutes` | 通过 |
| Cursor | `cursor` | 品牌 SVG | `ProviderCursor` | 通过 |
| 火山方舟 | `volcengine` | 品牌 SVG | `ProviderVolcengine` | 通过 |
| xAI API | `xaiAPI` | 品牌 SVG | `ProviderXAIAPI` | 通过 |
| IBM Bob | `ibmBob` | 品牌 SVG | `ProviderIBMBob` | 通过 |
| Warp | `warp` | 通用 SVG | `ProviderWarp` | 通过 |
| v0 | `v0` | 品牌 SVG | `ProviderV0` | 通过 |
| DevPass | `devPass` | 通用 SVG | `ProviderDevPass` | 通过 |
