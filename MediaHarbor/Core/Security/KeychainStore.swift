import Foundation
import Security

final class KeychainStore {
    private enum SynchronizableMode {
        case any
        case enabled
        case disabled
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                return "钥匙串操作失败，状态码：\(status)。"
            case .invalidData:
                return "钥匙串返回了无效数据。"
            }
        }
    }

    private let synchronizable: Bool

    init(synchronizable: Bool = true) {
        self.synchronizable = synchronizable
    }

    func save(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        try deleteMatchingAny(service: service, account: account)

        do {
            try add(data: data, service: service, account: account, synchronizableMode: synchronizable ? .enabled : .disabled)
        } catch {
            guard synchronizable else {
                throw error
            }

            try add(data: data, service: service, account: account, synchronizableMode: .disabled)
        }
    }

    func read(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account, synchronizableMode: .any)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }

            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account, synchronizableMode: .any) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func add(data: Data, service: String, account: String, synchronizableMode: SynchronizableMode) throws {
        var item = baseQuery(service: service, account: account, synchronizableMode: synchronizableMode)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    private func deleteMatchingAny(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account, synchronizableMode: .any) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(service: String, account: String, synchronizableMode: SynchronizableMode) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        switch synchronizableMode {
        case .any:
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        case .enabled:
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        case .disabled:
            break
        }

        return query
    }
}
