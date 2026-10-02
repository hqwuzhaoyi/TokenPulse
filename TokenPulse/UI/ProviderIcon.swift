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
        case .poe: "ProviderPoe"
        case .vercelAIGateway: "ProviderVercel"
        case .kimiCode: "ProviderKimiCode"
        case .elevenLabs: "ProviderElevenLabs"
        case .stepFun: "ProviderStepFun"
        case .newAPI: "ProviderNewAPI"
        case .copilot: "ProviderCopilot"
        case .volcengine: "ProviderVolcengine"
        case .xaiAPI: "ProviderXAIAPI"
        case .ibmBob: "ProviderIBMBob"
        }
    }

    var systemIconName: String? {
        nil
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
