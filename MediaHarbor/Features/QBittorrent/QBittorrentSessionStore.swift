import Foundation

final class QBittorrentSessionStore {
    private enum Constants {
        static let snapshotKey = "qbittorrent.snapshot"
        static let keychainService = "com.mk.MediaHarbor.qbittorrent"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func loadSession() -> QBittorrentSessionSnapshot? {
        guard let data = defaults.data(forKey: Constants.snapshotKey) else {
            return nil
        }

        return try? decoder.decode(QBittorrentSessionSnapshot.self, from: data)
    }

    func loadPassword(for session: QBittorrentSessionSnapshot) -> String? {
        try? keychain.read(service: Constants.keychainService, account: session.accountKey)
    }

    func save(session: QBittorrentSessionSnapshot, password: String) throws {
        if let existing = loadSession(), existing.accountKey != session.accountKey {
            try? keychain.delete(service: Constants.keychainService, account: existing.accountKey)
        }

        let data = try encoder.encode(session)
        defaults.set(data, forKey: Constants.snapshotKey)
        try keychain.save(password, service: Constants.keychainService, account: session.accountKey)
    }

    func clear() {
        if let session = loadSession() {
            try? keychain.delete(service: Constants.keychainService, account: session.accountKey)
        }

        defaults.removeObject(forKey: Constants.snapshotKey)
    }
}
