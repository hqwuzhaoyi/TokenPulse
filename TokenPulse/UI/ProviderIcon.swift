import SwiftUI

struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 20

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var image: Image {
        if let systemName = provider.systemIconName {
            return Image(systemName: systemName)
        }
        if let assetName = provider.iconAssetName {
            return Image(assetName).renderingMode(.template)
        }
        return Image(systemName: "questionmark.circle")
    }
}

extension Provider {
    var iconAssetName: String? {
        switch self {
        case .claude: "ProviderClaude"
        case .codex, .openAIAPI: "ProviderCodex"
        case .openCodeGo: "ProviderOpenCode"
        case .zai, .zhipu: "ProviderZai"
        case .miniMaxChina, .miniMaxInternational: "ProviderMiniMax"
        case .superGrok: "ProviderSuperGrok"
        case .qoderInternational, .qoderChina: "ProviderQoder"
        case .antigravity: "ProviderAntigravity"
        case .deepSeek: "ProviderDeepSeek"
        case .notionAI: "ProviderNotionAI"
        case .perplexity: "ProviderPerplexity"
        case .abacus: nil
        case .venice: "ProviderVenice"
        case .qwenCloud: "ProviderQwenCloud"
        case .raycastAI, .t3Chat, .zoomMate, .typeSafe: nil
        case .hyper: nil
        case .deepInfra: "ProviderDeepInfra"
        case .kiloCode: "ProviderKiloCode"
        case .atlasCloud: "ProviderAtlasCloud"
        case .poe: "ProviderPoe"
        case .vercelAIGateway: "ProviderVercel"
        case .kimiCode: "ProviderKimiCode"
        case .elevenLabs: "ProviderElevenLabs"
        case .stepFun: "ProviderStepFun"
        case .newAPI: "ProviderNewAPI"
        case .sub2api: "ProviderSub2API"
        case .bifrost, .liteLLM, .llmProxy: nil
        case .copilot: "ProviderCopilot"
        case .clinePass: "ProviderClinePass"
        case .clawRouter: "ProviderClawRouter"
        case .aixy: nil
        case .neuralwatt: nil
        case .codebuff: nil
        case .moonshot: "ProviderMoonshot"
        case .factory: "ProviderFactory"
        case .augmentCode: "ProviderAugmentCode"
        case .zed: "ProviderZed"
        case .grokBot: "ProviderGrokBot"
        case .gemini: "ProviderGemini"
        case .commandCode: "ProviderCommandCode"
        case .amp: "ProviderAmp"
        case .gitKraken: "ProviderGitKraken"
        case .huggingFace: "ProviderHuggingFace"
        case .synthetic, .v2ex, .xKiro: nil
        case .zenMux: "ProviderZenMux"
        case .alibabaCodingPlan, .alibabaTokenPlan: "ProviderAlibabaCloud"
        case .chutes: "ProviderChutes"
        case .cursor: "ProviderCursor"
        case .volcengine: "ProviderVolcengine"
        case .xaiAPI: "ProviderXAIAPI"
        case .ibmBob: "ProviderIBMBob"
        case .warp: "ProviderWarp"
        case .xiaomiCodingPlan: "ProviderXiaomiMiMo"
        case .ollamaCloud: "ProviderOllama"
        case .longCat: "ProviderLongCat"
        case .v0: "ProviderV0"
        case .devPass: "ProviderDevPass"
        case .devin: "ProviderDevin"
        case .manus: "ProviderManus"
        case .windsurf: "ProviderWindsurf"
        case .replicate: "ProviderReplicate"
        case .mistral: "ProviderMistral"
        case .sakana: "ProviderSakana"
        }
    }

    var systemIconName: String? {
        switch self {
        case .typeSafe: "puzzlepiece.extension.fill"
        case .raycastAI: "sparkles"
        case .t3Chat: "bubble.left.and.bubble.right.fill"
        case .zoomMate: "video.fill"
        case .codebuff: "terminal"
        case .abacus: "square.grid.3x3.fill"
        case .neuralwatt: "bolt.circle"
        case .aixy: "network"
        case .hyper: "bolt.circle"
        case .synthetic, .xKiro, .bifrost, .liteLLM, .llmProxy: "puzzlepiece.extension.fill"
        case .v2ex: "bubble.left.and.bubble.right.fill"
        default: nil
        }
    }
}

#Preview("Provider icons") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(Provider.allCases) { provider in
            HStack(spacing: 12) {
                ProviderIcon(provider: provider, size: 28)
                Text(provider.displayName)
            }
        }
    }
    .padding()
}
