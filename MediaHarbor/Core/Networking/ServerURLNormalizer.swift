import Foundation

enum ServerURLNormalizer {
    static func normalize(_ rawValue: String, defaultScheme: String, defaultPort: Int) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let value = trimmed.contains("://") ? trimmed : "\(defaultScheme)://\(trimmed)"
        guard var components = URLComponents(string: value) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        guard let host = components.host, host.isEmpty == false else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        components.query = nil
        components.fragment = nil

        if components.port == nil {
            components.port = defaultPort
        }

        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }
}
