import SwiftUI

struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 20

    var body: some View {
        Image(provider.iconAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Provider {
    var iconAssetName: String {
        switch self {
        case .claude: "ProviderClaude"
        case .codex: "ProviderCodex"
        case .zai: "ProviderZai"
        case .miniMaxChina: "ProviderMiniMax"
        case .superGrok: "ProviderSuperGrok"
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
