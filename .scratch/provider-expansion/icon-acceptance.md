# Provider 图标验收

2026-10-03，按用户指定的“实现完成 + 图标存在”标准检查当前78个provider。此项确认映射及资源存在，不代替真实账号/物理设备观察。

78个映射均存在：62个provider引用57个SVG image sets，16个provider使用8种系统SF Symbol。所有SVG均可解析、有明确尺寸、无currentColor；image set开启vector preservation与template rendering。8种SF Symbol已使用本机AppKit逐一确认存在（/tmp/tokenpulse-wave4-symbols.swift）。19个通用图标为16个SF映射与DevPass/Warp/Zed的3个通用SVG，不冒称品牌授权logo。

新增Gemini、Antigravity、Kiro、Nous使用固定Lobe Icons来源；OpenAI Legacy和Alibaba Token Plan复用已记录资源；JetBrains使用已存在的terminal系统符号。来源、固定提交、路径、版权和许可见 [ProviderIconNotices](../../TokenPulse/Resources/ProviderIconNotices.txt)。完整unsigned App/Watch/两端Widgets编译结果见[第四批验证记录](wave4-progress.md)。

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
| sub2api | `sub2api` | 品牌 SVG | `ProviderSub2API` | 通过 |
| Bifrost | `bifrost` | SF Symbol（通用） | `puzzlepiece.extension.fill` | 通过 |
| LiteLLM | `liteLLM` | SF Symbol（通用） | `puzzlepiece.extension.fill` | 通过 |
| LLM API Key Proxy | `llmProxy` | SF Symbol（通用） | `puzzlepiece.extension.fill` | 通过 |
| GitHub Copilot | `copilot` | 品牌 SVG | `ProviderCopilot` | 通过 |
| ClinePass | `clinePass` | 品牌 SVG | `ProviderClinePass` | 通过 |
| ClawRouter | `clawRouter` | 品牌 SVG | `ProviderClawRouter` | 通过 |
| Aixy | `aixy` | SF Symbol（通用） | `network` | 通过 |
| Neuralwatt | `neuralwatt` | SF Symbol（通用） | `bolt.circle` | 通过 |
| Codebuff | `codebuff` | SF Symbol（通用） | `terminal` | 通过 |
| Moonshot API 钱包 | `moonshot` | 品牌 SVG | `ProviderMoonshot` | 通过 |
| Factory | `factory` | 品牌 SVG | `ProviderFactory` | 通过 |
| Augment Code | `augmentCode` | 品牌 SVG | `ProviderAugmentCode` | 通过 |
| Zed | `zed` | 通用 SVG | `ProviderZed` | 通过 |
| Grok Bot | `grokBot` | 品牌 SVG | `ProviderGrokBot` | 通过 |
| Gemini Code Assist | `gemini` | 品牌 SVG | `ProviderGemini` | 通过 |
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
| 阿里百炼 Token Plan | `alibabaTokenPlan` | 品牌 SVG | `ProviderAlibabaCloud` | 通过 |
| Chutes | `chutes` | 品牌 SVG | `ProviderChutes` | 通过 |
| Cursor | `cursor` | 品牌 SVG | `ProviderCursor` | 通过 |
| 火山方舟 | `volcengine` | 品牌 SVG | `ProviderVolcengine` | 通过 |
| xAI API | `xaiAPI` | 品牌 SVG | `ProviderXAIAPI` | 通过 |
| IBM Bob | `ibmBob` | 品牌 SVG | `ProviderIBMBob` | 通过 |
| Warp | `warp` | 通用 SVG | `ProviderWarp` | 通过 |
| v0 | `v0` | 品牌 SVG | `ProviderV0` | 通过 |
| DevPass | `devPass` | 通用 SVG | `ProviderDevPass` | 通过 |
| Raycast AI | `raycastAI` | SF Symbol（通用） | `sparkles` | 通过 |
| T3 Chat | `t3Chat` | SF Symbol（通用） | `bubble.left.and.bubble.right.fill` | 通过 |
| ZoomMate | `zoomMate` | SF Symbol（通用） | `video.fill` | 通过 |
| Qwen Cloud | `qwenCloud` | 品牌 SVG | `ProviderQwenCloud` | 通过 |
| TypeSafe | `typeSafe` | SF Symbol（通用） | `puzzlepiece.extension.fill` | 通过 |
| Devin | `devin` | 品牌 SVG | `ProviderDevin` | 通过 |
| Manus | `manus` | 品牌 SVG | `ProviderManus` | 通过 |
| Windsurf | `windsurf` | 品牌 SVG | `ProviderWindsurf` | 通过 |
| Nous Portal | `nousPortal` | 品牌 SVG | `ProviderNousPortal` | 通过 |
| JetBrains AI | `jetBrainsAI` | SF Symbol（通用） | `terminal` | 通过 |
| Replicate | `replicate` | 品牌 SVG | `ProviderReplicate` | 通过 |
| Mistral | `mistral` | 品牌 SVG | `ProviderMistral` | 通过 |
| Sakana AI | `sakana` | 品牌 SVG | `ProviderSakana` | 通过 |
| Kiro | `kiro` | 品牌 SVG | `ProviderKiro` | 通过 |
| 小米 Coding Plan | `xiaomiCodingPlan` | 品牌 SVG | `ProviderXiaomiMiMo` | 通过 |
| Qoder 国内版 | `qoderChina` | 品牌 SVG | `ProviderQoder` | 通过 |
| Ollama Cloud | `ollamaCloud` | 品牌 SVG | `ProviderOllama` | 通过 |
| LongCat | `longCat` | 品牌 SVG | `ProviderLongCat` | 通过 |
| Notion AI | `notionAI` | 品牌 SVG | `ProviderNotionAI` | 通过 |
| Perplexity API | `perplexity` | 品牌 SVG | `ProviderPerplexity` | 通过 |
| Abacus AI | `abacus` | SF Symbol（通用） | `square.grid.3x3.fill` | 通过 |
| OpenAI API（Legacy 余额） | `openAIAPI` | 品牌 SVG | `ProviderCodex` | 通过 |
| Antigravity | `antigravity` | 品牌 SVG | `ProviderAntigravity` | 通过 |
