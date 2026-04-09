import Foundation

final class JellyfinSessionStore {
    private enum Constants {
        static let snapshotsKey = "jellyfin.snapshots"
        static let activeAccountKey = "jellyfin.active-account-key"
        static let inactiveAccountMarker = "__inactive__"
        static let keychainService = "com.mk.MediaHarbor.jellyfin"

        static let legacySnapshotKey = "jellyfin.snapshot"
        static let legacyKeychainAccount = "active-access-token"
    }

    private let storage: CloudBackedDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keychain: KeychainStore

    init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore? = nil,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.storage = CloudBackedDefaults(defaults: defaults, cloudStore: cloudStore)
        self.keychain = keychain
    }

    func loadSessions() -> [JellyfinSessionSnapshot] {
        if let data = storage.data(forKey: Constants.snapshotsKey),
           let sessions = try? decoder.decode([JellyfinSessionSnapshot].self, from: data) {
            return deduplicated(sessions)
        }

        if let data = storage.data(forKey: Constants.legacySnapshotKey),
           let session = try? decoder.decode(JellyfinSessionSnapshot.self, from: data) {
            return [session]
        }

        return []
    }

    func loadActiveSession() -> JellyfinSessionSnapshot? {
        let sessions = loadSessions()
        guard sessions.isEmpty == false else {
            return nil
        }

        if let activeAccountKey = storage.string(forKey: Constants.activeAccountKey) {
            if activeAccountKey == Constants.inactiveAccountMarker {
                return nil
            }

            if let session = sessions.first(where: { $0.accountKey == activeAccountKey }) {
                return session
            }
        }

        return sessions.first
    }

    func save(session: JellyfinSessionSnapshot, accessToken: String) throws {
        var sessions = loadSessions().filter { $0.accountKey != session.accountKey }
        sessions.insert(session, at: 0)

        try saveSessions(sessions)
        storage.set(session.accountKey, forKey: Constants.activeAccountKey)
        try keychain.save(accessToken, service: Constants.keychainService, account: session.accountKey)

        clearLegacyStorage()
    }

    func activate(session: JellyfinSessionSnapshot) {
        storage.set(session.accountKey, forKey: Constants.activeAccountKey)
    }

    func clearActiveSession() {
        storage.set(Constants.inactiveAccountMarker, forKey: Constants.activeAccountKey)
    }

    @discardableResult
    func remove(session: JellyfinSessionSnapshot) -> JellyfinSessionSnapshot? {
        let sessions = loadSessions().filter { $0.accountKey != session.accountKey }

        if sessions.isEmpty {
            storage.removeObject(forKey: Constants.snapshotsKey)
            storage.removeObject(forKey: Constants.activeAccountKey)
        } else {
            try? saveSessions(sessions)

            if storage.string(forKey: Constants.activeAccountKey) == session.accountKey {
                storage.set(sessions[0].accountKey, forKey: Constants.activeAccountKey)
            }
        }

        try? keychain.delete(service: Constants.keychainService, account: session.accountKey)

        if isLegacySession(session) {
            clearLegacyStorage()
        }

        return loadActiveSession()
    }

    func loadAccessToken(for session: JellyfinSessionSnapshot) -> String? {
        if let token = try? keychain.read(service: Constants.keychainService, account: session.accountKey) {
            return token
        }

        guard isLegacySession(session) else {
            return nil
        }

        return try? keychain.read(service: Constants.keychainService, account: Constants.legacyKeychainAccount)
    }

    func clear() {
        let sessions = loadSessions()
        for session in sessions {
            try? keychain.delete(service: Constants.keychainService, account: session.accountKey)
        }

        storage.removeObject(forKey: Constants.snapshotsKey)
        storage.removeObject(forKey: Constants.activeAccountKey)
        clearLegacyStorage()
    }

    private func saveSessions(_ sessions: [JellyfinSessionSnapshot]) throws {
        let data = try encoder.encode(deduplicated(sessions))
        storage.set(data, forKey: Constants.snapshotsKey)
    }

    private func deduplicated(_ sessions: [JellyfinSessionSnapshot]) -> [JellyfinSessionSnapshot] {
        var seenKeys = Set<String>()
        var orderedSessions: [JellyfinSessionSnapshot] = []

        for session in sessions {
            if seenKeys.insert(session.accountKey).inserted {
                orderedSessions.append(session)
            }
        }

        return orderedSessions
    }

    private func isLegacySession(_ session: JellyfinSessionSnapshot) -> Bool {
        guard let data = storage.data(forKey: Constants.legacySnapshotKey),
              let legacySession = try? decoder.decode(JellyfinSessionSnapshot.self, from: data) else {
            return false
        }

        return legacySession.accountKey == session.accountKey
    }

    private func clearLegacyStorage() {
        storage.removeObject(forKey: Constants.legacySnapshotKey)
        try? keychain.delete(service: Constants.keychainService, account: Constants.legacyKeychainAccount)
    }
}
