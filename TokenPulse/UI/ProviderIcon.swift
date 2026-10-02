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
        case .codex: "ProviderCodex"
        case .openCodeGo: "ProviderOpenCode"
        case .zai, .zhipu: "ProviderZai"
        case .miniMaxChina, .miniMaxInternational: "ProviderMiniMax"
        case .superGrok: "ProviderSuperGrok"
        case .qoderInternational: "ProviderQoder"
        case .deepSeek: "ProviderDeepSeek"
        case .venice: "ProviderVenice"
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
        case .copilot: "ProviderCopilot"
        case .clinePass: "ProviderClinePass"
        case .clawRouter: "ProviderClawRouter"
        case .aixy: nil
        case .neuralwatt: nil
        case .codebuff: nil
        case .moonshot: "ProviderMoonshot"
        case .factory: "ProviderFactory"
        case .commandCode: "ProviderCommandCode"
        case .amp: "ProviderAmp"
        case .gitKraken: "ProviderGitKraken"
        case .huggingFace: "ProviderHuggingFace"
        case .synthetic, .v2ex, .xKiro: nil
        case .zenMux: "ProviderZenMux"
        case .alibabaCodingPlan: "ProviderAlibabaCloud"
        case .chutes: "ProviderChutes"
        case .cursor: "ProviderCursor"
        case .volcengine: "ProviderVolcengine"
        case .xaiAPI: "ProviderXAIAPI"
        case .ibmBob: "ProviderIBMBob"
        case .warp: "ProviderWarp"
        case .v0: "ProviderV0"
        case .devPass: "ProviderDevPass"
        case .devin: "ProviderDevin"
        case .manus: "ProviderManus"
        }
    }

    var systemIconName: String? {
        switch self {
        case .codebuff: "terminal"
        case .neuralwatt: "bolt.circle"
        case .aixy: "network"
        case .hyper: "bolt.circle"
        case .synthetic, .xKiro: "puzzlepiece.extension.fill"
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
