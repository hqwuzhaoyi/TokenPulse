# Provider 图标验收

2026-10-02，按用户最新要求：完整接入实现且图标存在即可验收，不再以真实账号/设备作为接入关票条件。此记录依据0477a43的71个provider映射，全部已集成且无缺图；不包括7家仍在可行性研究的来源，不以图标假称它们已接入。

71映射实查：56个provider映射到53个SVG image sets（MiniMax、Z.ai/智谱、Qoder地区复用），15个使用8种SF Symbol。53套映射资源文件都存在且XML可解析、明确尺寸、无currentColor，image sets开启vector preservation和template rendering。root已实际查询8种系统符号均存在；本次文档工作者仅静态复核映射、资源与metadata，没有运行Xcode/模拟器或改变资源。最终71入口unsigned构建已实际通过（代码4adb520，/tmp/tokenpulse-wave3-final-unsigned.log），覆盖App、Watch、两端Widgets与资产目录。

许可来源主要为Lobe Icons及各官方仓库，固定提交/路径/版权/许可见 `TokenPulse/Resources/ProviderIconNotices.txt`，本次未修改notices或图形。通用图标共18个：15个SF映射加DevPass/Warp/Zed的3套通用SVG。它们满足图标存在，但通用符号不称官方品牌logo；GitKraken使用已许可官方GitLens客户端符号，也不冒称未有许可的站点mark。

8种系统符号为：`puzzlepiece.extension.fill`、`sparkles`、`bubble.left.and.bubble.right.fill`、`video.fill`、`terminal`、`square.grid.3x3.fill`、`bolt.circle`、`network`。下表各行“通过”只表示当前图标存在，和真实授权、生产字段、物理Watch、全部尺寸视觉以及Pi审查结果分开；62接入票done、7研究awaiting-validation。

| Provider | 枚举 | 类型 | 映射 | 结果 |
| --- | --- | --- | --- | --- |
| MiniMax 国内版 | `miniMaxChina` | SVG (brand/client) | `ProviderMiniMax` | 通过 |
| Claude | `claude` | SVG (brand/client) | `ProviderClaude` | 通过 |
| Codex | `codex` | SVG (brand/client) | `ProviderCodex` | 通过 |
| OpenCode Go | `openCodeGo` | SVG (brand/client) | `ProviderOpenCode` | 通过 |
| Z.ai | `zai` | SVG (brand/client) | `ProviderZai` | 通过 |
| SuperGrok | `superGrok` | SVG (brand/client) | `ProviderSuperGrok` | 通过 |
| Qoder 国际版 | `qoderInternational` | SVG (brand/client) | `ProviderQoder` | 通过 |
| DeepSeek | `deepSeek` | SVG (brand/client) | `ProviderDeepSeek` | 通过 |
| Kimi Code 国内版 | `kimiCode` | SVG (brand/client) | `ProviderKimiCode` | 通过 |
| ElevenLabs | `elevenLabs` | SVG (brand/client) | `ProviderElevenLabs` | 通过 |
| Poe | `poe` | SVG (brand/client) | `ProviderPoe` | 通过 |
| Vercel AI Gateway | `vercelAIGateway` | SVG (brand/client) | `ProviderVercel` | 通过 |
| 智谱国内版 | `zhipu` | SVG (brand/client) | `ProviderZai` | 通过 |
| MiniMax 国际版 | `miniMaxInternational` | SVG (brand/client) | `ProviderMiniMax` | 通过 |
| StepFun | `stepFun` | SVG (brand/client) | `ProviderStepFun` | 通过 |
| New API | `newAPI` | SVG (brand/client) | `ProviderNewAPI` | 通过 |
| sub2api | `sub2api` | SVG (brand/client) | `ProviderSub2API` | 通过 |
| Bifrost | `bifrost` | SF Symbol (generic) | `puzzlepiece.extension.fill` | 通过 |
| LiteLLM | `liteLLM` | SF Symbol (generic) | `puzzlepiece.extension.fill` | 通过 |
| LLM API Key Proxy | `llmProxy` | SF Symbol (generic) | `puzzlepiece.extension.fill` | 通过 |
| GitHub Copilot | `copilot` | SVG (brand/client) | `ProviderCopilot` | 通过 |
| ClinePass | `clinePass` | SVG (brand/client) | `ProviderClinePass` | 通过 |
| ClawRouter | `clawRouter` | SVG (brand/client) | `ProviderClawRouter` | 通过 |
| Aixy | `aixy` | SF Symbol (generic) | `network` | 通过 |
| Neuralwatt | `neuralwatt` | SF Symbol (generic) | `bolt.circle` | 通过 |
| Codebuff | `codebuff` | SF Symbol (generic) | `terminal` | 通过 |
| Moonshot API 钱包 | `moonshot` | SVG (brand/client) | `ProviderMoonshot` | 通过 |
| Factory | `factory` | SVG (brand/client) | `ProviderFactory` | 通过 |
| Augment Code | `augmentCode` | SVG (brand/client) | `ProviderAugmentCode` | 通过 |
| Zed | `zed` | SVG (generic) | `ProviderZed` | 通过 |
| Grok Bot | `grokBot` | SVG (brand/client) | `ProviderGrokBot` | 通过 |
| Venice | `venice` | SVG (brand/client) | `ProviderVenice` | 通过 |
| Hyper | `hyper` | SF Symbol (generic) | `bolt.circle` | 通过 |
| DeepInfra | `deepInfra` | SVG (brand/client) | `ProviderDeepInfra` | 通过 |
| Kilo Code | `kiloCode` | SVG (brand/client) | `ProviderKiloCode` | 通过 |
| Atlas Cloud | `atlasCloud` | SVG (brand/client) | `ProviderAtlasCloud` | 通过 |
| Command Code | `commandCode` | SVG (brand/client) | `ProviderCommandCode` | 通过 |
| Amp | `amp` | SVG (brand/client) | `ProviderAmp` | 通过 |
| GitKraken AI | `gitKraken` | SVG (brand/client) | `ProviderGitKraken` | 通过 |
| Hugging Face | `huggingFace` | SVG (brand/client) | `ProviderHuggingFace` | 通过 |
| Synthetic | `synthetic` | SF Symbol (generic) | `puzzlepiece.extension.fill` | 通过 |
| V2EX | `v2ex` | SF Symbol (generic) | `bubble.left.and.bubble.right.fill` | 通过 |
| xKiro | `xKiro` | SF Symbol (generic) | `puzzlepiece.extension.fill` | 通过 |
| ZenMux | `zenMux` | SVG (brand/client) | `ProviderZenMux` | 通过 |
| 阿里百炼 Coding Plan | `alibabaCodingPlan` | SVG (brand/client) | `ProviderAlibabaCloud` | 通过 |
| Chutes | `chutes` | SVG (brand/client) | `ProviderChutes` | 通过 |
| Cursor | `cursor` | SVG (brand/client) | `ProviderCursor` | 通过 |
| 火山方舟 | `volcengine` | SVG (brand/client) | `ProviderVolcengine` | 通过 |
| xAI API | `xaiAPI` | SVG (brand/client) | `ProviderXAIAPI` | 通过 |
| IBM Bob | `ibmBob` | SVG (brand/client) | `ProviderIBMBob` | 通过 |
| Warp | `warp` | SVG (generic) | `ProviderWarp` | 通过 |
| v0 | `v0` | SVG (brand/client) | `ProviderV0` | 通过 |
| DevPass | `devPass` | SVG (generic) | `ProviderDevPass` | 通过 |
| Raycast AI | `raycastAI` | SF Symbol (generic) | `sparkles` | 通过 |
| T3 Chat | `t3Chat` | SF Symbol (generic) | `bubble.left.and.bubble.right.fill` | 通过 |
| ZoomMate | `zoomMate` | SF Symbol (generic) | `video.fill` | 通过 |
| Qwen Cloud | `qwenCloud` | SVG (brand/client) | `ProviderQwenCloud` | 通过 |
| TypeSafe | `typeSafe` | SF Symbol (generic) | `puzzlepiece.extension.fill` | 通过 |
| Devin | `devin` | SVG (brand/client) | `ProviderDevin` | 通过 |
| Manus | `manus` | SVG (brand/client) | `ProviderManus` | 通过 |
| Windsurf | `windsurf` | SVG (brand/client) | `ProviderWindsurf` | 通过 |
| Replicate | `replicate` | SVG (brand/client) | `ProviderReplicate` | 通过 |
| Mistral | `mistral` | SVG (brand/client) | `ProviderMistral` | 通过 |
| Sakana AI | `sakana` | SVG (brand/client) | `ProviderSakana` | 通过 |
| 小米 Coding Plan | `xiaomiCodingPlan` | SVG (brand/client) | `ProviderXiaomiMiMo` | 通过 |
| Qoder 国内版 | `qoderChina` | SVG (brand/client) | `ProviderQoder` | 通过 |
| Ollama Cloud | `ollamaCloud` | SVG (brand/client) | `ProviderOllama` | 通过 |
| LongCat | `longCat` | SVG (brand/client) | `ProviderLongCat` | 通过 |
| Notion AI | `notionAI` | SVG (brand/client) | `ProviderNotionAI` | 通过 |
| Perplexity API | `perplexity` | SVG (brand/client) | `ProviderPerplexity` | 通过 |
| Abacus AI | `abacus` | SF Symbol (generic) | `square.grid.3x3.fill` | 通过 |
