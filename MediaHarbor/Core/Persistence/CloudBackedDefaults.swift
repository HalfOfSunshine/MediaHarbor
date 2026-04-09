import Foundation

final class CloudBackedDefaults {
    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore?

    init(defaults: UserDefaults = .standard, cloudStore: NSUbiquitousKeyValueStore? = nil) {
        self.defaults = defaults
        self.cloudStore = cloudStore ?? (defaults === UserDefaults.standard ? .default : nil)
        self.cloudStore?.synchronize()
    }

    func object(forKey key: String) -> Any? {
        if let cloudStore, let object = cloudStore.object(forKey: key) {
            persistLocally(object, forKey: key)
            return object
        }

        return defaults.object(forKey: key)
    }

    func string(forKey key: String) -> String? {
        if let cloudStore, let value = cloudStore.string(forKey: key) {
            defaults.set(value, forKey: key)
            return value
        }

        return defaults.string(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        if let cloudStore, let value = cloudStore.data(forKey: key) {
            defaults.set(value, forKey: key)
            return value
        }

        return defaults.data(forKey: key)
    }

    func bool(forKey key: String) -> Bool? {
        if let cloudStore, cloudStore.object(forKey: key) != nil {
            let value = cloudStore.bool(forKey: key)
            defaults.set(value, forKey: key)
            return value
        }

        guard defaults.object(forKey: key) != nil else {
            return nil
        }

        return defaults.bool(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
            cloudStore?.set(value, forKey: key)
        } else {
            removeObject(forKey: key)
            return
        }

        cloudStore?.synchronize()
    }

    func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
        cloudStore?.removeObject(forKey: key)
        cloudStore?.synchronize()
    }

    private func persistLocally(_ object: Any, forKey key: String) {
        switch object {
        case let value as String:
            defaults.set(value, forKey: key)
        case let value as Data:
            defaults.set(value, forKey: key)
        case let value as NSNumber:
            defaults.set(value, forKey: key)
        case let value as NSArray:
            defaults.set(value, forKey: key)
        case let value as NSDictionary:
            defaults.set(value, forKey: key)
        default:
            break
        }
    }
}
