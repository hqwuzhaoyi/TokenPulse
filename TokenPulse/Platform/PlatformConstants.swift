import Foundation

enum PlatformConstants {
    static let appGroupIdentifier = "group.com.tokenpulse.58m23c5wlr.shared"
    static let credentialService = "com.tokenpulse.credentials"
    static let backgroundRefreshIdentifier = "com.tokenpulse.app.refresh"
    static let accountDeepLinkScheme = "tokenpulse"

    static var resolvedKeychainAccessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "TokenPulseKeychainAccessGroup") as? String
    }
}
