import Foundation
import CryptoKit

/// OKX API 配置：密钥保存在 iOS Keychain，模拟盘/实盘一键切换
final class OKXConfig: ObservableObject {
    static let shared = OKXConfig()

    static let liveBaseURL = "https://www.okx.com"
    static let wsPublicURL = "wss://ws.okx.com:8443/ws/v5/public"
    static let wsPrivateURL = "wss://ws.okx.com:8443/ws/v5/private"

    @Published var apiKey: String {
        didSet { KeychainStore.set(apiKey, forKey: "okx_api_key") }
    }
    @Published var secretKey: String {
        didSet { KeychainStore.set(secretKey, forKey: "okx_secret_key") }
    }
    @Published var passphrase: String {
        didSet { KeychainStore.set(passphrase, forKey: "okx_passphrase") }
    }
    /// true = 模拟盘（Demo Trading），false = 实盘
    @Published var isDemo: Bool {
        didSet { UserDefaults.standard.set(isDemo, forKey: "okx_is_demo") }
    }
    /// AI 服务（OpenAI 兼容接口）
    @Published var aiBaseURL: String {
        didSet { UserDefaults.standard.set(aiBaseURL, forKey: "ai_base_url") }
    }
    @Published var aiAPIKey: String {
        didSet { KeychainStore.set(aiAPIKey, forKey: "ai_api_key") }
    }
    @Published var aiModel: String {
        didSet { UserDefaults.standard.set(aiModel, forKey: "ai_model") }
    }

    var baseURL: String { Self.liveBaseURL }
    var isConfigured: Bool { !apiKey.isEmpty && !secretKey.isEmpty && !passphrase.isEmpty }

    private init() {
        apiKey = KeychainStore.get("okx_api_key") ?? ""
        secretKey = KeychainStore.get("okx_secret_key") ?? ""
        passphrase = KeychainStore.get("okx_passphrase") ?? ""
        isDemo = UserDefaults.standard.bool(forKey: "okx_is_demo")
        aiBaseURL = UserDefaults.standard.string(forKey: "ai_base_url") ?? "https://api.openai.com/v1"
        aiAPIKey = KeychainStore.get("ai_api_key") ?? ""
        aiModel = UserDefaults.standard.string(forKey: "ai_model") ?? "gpt-4o-mini"
    }

    /// HMAC-SHA256 签名（OKX V5 规范：timestamp + method + requestPath + body）
    func sign(timestamp: String, method: String, requestPath: String, body: String) -> String {
        let message = timestamp + method + requestPath + body
        let key = Data(secretKey.utf8)
        let data = Data(message.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac).base64EncodedString()
    }
}

/// iOS Keychain 简易封装
enum KeychainStore {
    static func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
