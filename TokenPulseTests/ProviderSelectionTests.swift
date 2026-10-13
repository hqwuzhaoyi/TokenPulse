import Foundation
import XCTest
@testable import TokenPulse

final class ProviderSelectionTests: XCTestCase {
    func testProviderSearchRetainsChineseEnglishAndBrandAliasesInEitherLanguage() {
        for language in ["zh-Hans", "en", "fr"] {
            let catalog = ProviderSelectionCatalog(existingProviders: [.claude], language: language)
            XCTAssertEqual(Set(catalog.results(for: "智谱")), [.zhipu, .zai])
            XCTAssertEqual(Set(catalog.results(for: "Z.h.i.p.u")), [.zhipu, .zai])
            XCTAssertEqual(Set(catalog.results(for: "百炼")), [.alibabaCodingPlan, .alibabaTokenPlan])
            XCTAssertEqual(catalog.results(for: "MiniMax 国内"), [.miniMaxChina])
            XCTAssertEqual(catalog.results(for: "Moonshot API Wallet"), [.moonshot])
            XCTAssertEqual(catalog.results(for: "Claude"), [.claude])
            XCTAssertTrue(catalog.results(for: "nonexistent-provider-fixture").isEmpty)
        }
    }

    func testDisplayedSectionsAndNativeIndexAgreeAndKeepAddedProvidersSeparate() {
        let added: Set<Provider> = [.claude, .miniMaxChina, .alibabaCodingPlan]
        for language in ["zh-Hans", "en"] {
            let catalog = ProviderSelectionCatalog(existingProviders: added, language: language)
            XCTAssertEqual(Set(catalog.addedProviders), added)
            let remaining = catalog.sections.flatMap(\.providers)
            XCTAssertEqual(Set(remaining), Set(Provider.allCases).subtracting(added))
            XCTAssertEqual(remaining.count, Set(remaining).count)
            XCTAssertEqual(Set(catalog.sections.map(\.indexLabel)).count, catalog.sections.count)
            for section in catalog.sections {
                if section.indexLabel == "#" {
                    XCTAssertEqual(section.title, language == "en" ? "Other" : "其他")
                    XCTAssertEqual(catalog.sections.last?.indexLabel, "#")
                } else {
                    XCTAssertEqual(section.title, section.indexLabel)
                }
                for provider in section.providers {
                    let initial = String(provider.displayName(language: language).prefix(1)).uppercased()
                    let expectedIndex = initial.range(of: "^[A-Z]$", options: .regularExpression) == nil ? "#" : initial
                    XCTAssertEqual(section.indexLabel, expectedIndex)
                }
                for (first, second) in zip(section.providers, section.providers.dropFirst()) {
                    XCTAssertNotEqual(first.displayName(language: language)
                        .localizedStandardCompare(second.displayName(language: language)), .orderedDescending)
                }
            }
        }
        let english = ProviderSelectionCatalog(existingProviders: [], language: "en")
        let chinese = ProviderSelectionCatalog(existingProviders: [], language: "zh-Hans")
        XCTAssertTrue(english.sections.first { $0.indexLabel == "Z" }?.providers.contains(.zhipu) == true)
        XCTAssertTrue(chinese.sections.first { $0.indexLabel == "#" }?.providers.contains(.zhipu) == true)
    }

    func testTranslatedRegionDescriptionsDoNotChangeSavedProviderAndCredentialScope() throws {
        let name = "研究 · Moonshot 🌙"
        let controller = ProviderAuthenticationController()
        for language in ["zh-Hans", "en", "fr"] {
            XCTAssertEqual(Provider.moonshot.displayName(language: language),
                           language == "zh-Hans" ? "Moonshot API 钱包" : "Moonshot API Wallet")
            XCTAssertEqual(ProviderRegion.china.displayName(language: language),
                           language == "zh-Hans" ? "国内（中国）" : "China")
            XCTAssertEqual(AlibabaTokenPlanSite.international.displayName(language: language),
                           language == "zh-Hans" ? "Alibaba Cloud 国际站" : "Alibaba Cloud International Site")
            let account = SubscriptionAccount(name: name, provider: .moonshot)
            let restored = try JSONDecoder().decode(SubscriptionAccount.self, from: JSONEncoder().encode(account))
            XCTAssertEqual(restored, account)
            XCTAssertEqual(restored.name, name)
            let credential = try controller.credential(provider: .moonshot, apiKey: " synthetic-fixture ", region: .china)
            let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: .moonshot)
            XCTAssertEqual(envelope.accessToken, "synthetic-fixture")
            XCTAssertEqual(envelope.metadata["region"], ProviderRegion.china.rawValue)
            XCTAssertThrowsError(try controller.credential(provider: .moonshot, apiKey: "synthetic-fixture"))
            XCTAssertEqual(RefreshFailure.network.rawValue, "network")
            XCTAssertEqual(RefreshFailure.network.displayName(language: language),
                           language == "zh-Hans" ? "网络连接失败" : "Network connection failed")
        }
    }
}
