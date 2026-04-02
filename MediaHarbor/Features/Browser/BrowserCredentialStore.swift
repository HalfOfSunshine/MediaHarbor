import Foundation

final class BrowserCredentialStore {
    private enum Constants {
        static let keychainService = "com.mk.MediaHarbor.browser"
    }

    private let keychain: KeychainStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func loadCredential(for siteID: String) -> BrowserCredential {
        guard let json = try? keychain.read(service: Constants.keychainService, account: siteID),
              let data = json.data(using: .utf8),
              let credential = try? decoder.decode(BrowserCredential.self, from: data) else {
            return .empty
        }

        return credential
    }

    func saveCredential(_ credential: BrowserCredential, for siteID: String) throws {
        let data = try encoder.encode(credential)
        let json = String(decoding: data, as: UTF8.self)
        try keychain.save(json, service: Constants.keychainService, account: siteID)
    }

    func deleteCredential(for siteID: String) {
        try? keychain.delete(service: Constants.keychainService, account: siteID)
    }
}
