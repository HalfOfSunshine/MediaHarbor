import Foundation

struct QBittorrentDashboard: Sendable {
    let transferInfo: QBittorrentTransferInfo
    let torrents: [QBTorrent]
}

struct QBittorrentAPIClient {
    enum APIError: LocalizedError {
        case invalidServerURL
        case invalidResponse
        case unauthorized
        case serverMessage(String)
        case transport(URLError)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .invalidServerURL:
                return "请输入有效的 qBittorrent 地址。"
            case .invalidResponse:
                return "qBittorrent 返回了无法识别的响应。"
            case .unauthorized:
                return "qBittorrent 登录失败，请检查账号密码。"
            case let .serverMessage(message):
                return message
            case let .transport(error):
                switch error.code {
                case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                    return "无法连接到 qBittorrent，请检查地址和网络连接。"
                case .appTransportSecurityRequiresSecureConnection:
                    return "当前构建阻止了不安全的 HTTP 连接。请使用 HTTPS，或者确认你运行的是用于本地调试的 Debug 构建。"
                case .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateUntrusted, .secureConnectionFailed:
                    return "qBittorrent 服务器的 TLS 证书无法被 iOS 信任。"
                default:
                    return error.localizedDescription
                }
            case .decoding:
                return "MediaHarbor 无法解析 qBittorrent 返回的数据。"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpShouldSetCookies = true
            self.session = URLSession(configuration: configuration)
        }
    }

    func connect(baseURL: URL, username: String, password: String) async throws -> String? {
        try await authenticate(baseURL: baseURL, username: username, password: password)
        return try await appVersion(baseURL: baseURL)
    }

    func dashboard(baseURL: URL, username: String, password: String) async throws -> QBittorrentDashboard {
        try await authenticate(baseURL: baseURL, username: username, password: password)

        async let fetchedTransferInfo = transferInfo(baseURL: baseURL)
        async let fetchedTorrents = torrents(baseURL: baseURL)

        return QBittorrentDashboard(
            transferInfo: try await fetchedTransferInfo,
            torrents: try await fetchedTorrents
        )
    }

    func pause(baseURL: URL, username: String, password: String, hash: String) async throws {
        try await authenticate(baseURL: baseURL, username: username, password: password)
        let request = try makeRequest(
            baseURL: baseURL,
            path: "api/v2/torrents/pause",
            method: "POST",
            formItems: [
                URLQueryItem(name: "hashes", value: hash),
            ]
        )
        try await sendVoid(request)
    }

    func resume(baseURL: URL, username: String, password: String, hash: String) async throws {
        try await authenticate(baseURL: baseURL, username: username, password: password)
        let request = try makeRequest(
            baseURL: baseURL,
            path: "api/v2/torrents/resume",
            method: "POST",
            formItems: [
                URLQueryItem(name: "hashes", value: hash),
            ]
        )
        try await sendVoid(request)
    }

    func delete(baseURL: URL, username: String, password: String, hash: String, deleteFiles: Bool) async throws {
        try await authenticate(baseURL: baseURL, username: username, password: password)
        let request = try makeRequest(
            baseURL: baseURL,
            path: "api/v2/torrents/delete",
            method: "POST",
            formItems: [
                URLQueryItem(name: "hashes", value: hash),
                URLQueryItem(name: "deleteFiles", value: deleteFiles ? "true" : "false"),
            ]
        )
        try await sendVoid(request)
    }

    private func authenticate(baseURL: URL, username: String, password: String) async throws {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "api/v2/auth/login",
            method: "POST",
            formItems: [
                URLQueryItem(name: "username", value: username),
                URLQueryItem(name: "password", value: password),
            ]
        )

        let message = try await sendText(request).trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.lowercased() == "ok." else {
            throw APIError.unauthorized
        }
    }

    private func appVersion(baseURL: URL) async throws -> String? {
        let request = try makeRequest(baseURL: baseURL, path: "api/v2/app/version")
        let version = try await sendText(request).trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    private func transferInfo(baseURL: URL) async throws -> QBittorrentTransferInfo {
        let request = try makeRequest(baseURL: baseURL, path: "api/v2/transfer/info")
        let dto: QBittorrentTransferInfoDTO = try await send(request)
        return dto.asTransferInfo
    }

    private func torrents(baseURL: URL) async throws -> [QBTorrent] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "api/v2/torrents/info",
            queryItems: [
                URLQueryItem(name: "sort", value: "added_on"),
                URLQueryItem(name: "reverse", value: "true"),
            ]
        )

        let dto: [QBTorrentDTO] = try await send(request)
        return dto.compactMap(\.asTorrent).sorted { lhs, rhs in
            switch (lhs.addedOn, rhs.addedOn) {
            case let (.some(lhsDate), .some(rhsDate)):
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func makeRequest(
        baseURL: URL,
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        formItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let endpoint = baseURL.appendingPathComponent(trimmedPath)

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidServerURL
        }

        if queryItems.isEmpty == false {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json, text/plain;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

        if formItems.isEmpty == false {
            request.httpBody = formBody(from: formItems)
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)

            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.transport(error)
        } catch {
            throw APIError.serverMessage(error.localizedDescription)
        }
    }

    private func sendText(_ request: URLRequest) async throws -> String {
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            return String(decoding: data, as: UTF8.self)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.transport(error)
        } catch {
            throw APIError.serverMessage(error.localizedDescription)
        }
    }

    private func sendVoid(_ request: URLRequest) async throws {
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.transport(error)
        } catch {
            throw APIError.serverMessage(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return
        case 403:
            throw APIError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, message.isEmpty == false {
                throw APIError.serverMessage(message)
            }

            throw APIError.invalidResponse
        }
    }

    private func formBody(from items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

private struct QBittorrentTransferInfoDTO: Decodable {
    let connectionStatus: String?
    let dhtNodes: Int?
    let downloadedData: Int64?
    let downloadSpeed: Int64?
    let downloadRateLimit: Int64?
    let uploadedData: Int64?
    let uploadSpeed: Int64?
    let uploadRateLimit: Int64?
    let externalAddressV4: String?
    let externalAddressV6: String?

    enum CodingKeys: String, CodingKey {
        case connectionStatus = "connection_status"
        case dhtNodes = "dht_nodes"
        case downloadedData = "dl_info_data"
        case downloadSpeed = "dl_info_speed"
        case downloadRateLimit = "dl_rate_limit"
        case uploadedData = "up_info_data"
        case uploadSpeed = "up_info_speed"
        case uploadRateLimit = "up_rate_limit"
        case externalAddressV4 = "last_external_address_v4"
        case externalAddressV6 = "last_external_address_v6"
    }

    var asTransferInfo: QBittorrentTransferInfo {
        QBittorrentTransferInfo(
            connectionStatus: connectionStatus,
            dhtNodes: dhtNodes,
            downloadedData: downloadedData ?? 0,
            downloadSpeed: downloadSpeed ?? 0,
            downloadRateLimit: downloadRateLimit,
            uploadedData: uploadedData ?? 0,
            uploadSpeed: uploadSpeed ?? 0,
            uploadRateLimit: uploadRateLimit,
            externalAddressV4: externalAddressV4,
            externalAddressV6: externalAddressV6
        )
    }
}

private struct QBTorrentDTO: Decodable {
    let hash: String?
    let name: String?
    let progress: Double?
    let state: String?
    let size: Int64?
    let totalSize: Int64?
    let downloaded: Int64?
    let uploaded: Int64?
    let downloadSpeed: Int64?
    let uploadSpeed: Int64?
    let eta: Int64?
    let ratio: Double?
    let category: String?
    let tags: String?
    let savePath: String?
    let addedOn: Int64?

    enum CodingKeys: String, CodingKey {
        case hash
        case name
        case progress
        case state
        case size
        case totalSize = "total_size"
        case downloaded
        case uploaded
        case downloadSpeed = "dlspeed"
        case uploadSpeed = "upspeed"
        case eta
        case ratio
        case category
        case tags
        case savePath = "save_path"
        case addedOn = "added_on"
    }

    var asTorrent: QBTorrent? {
        guard let hash, let name else {
            return nil
        }

        return QBTorrent(
            hash: hash,
            name: name,
            progress: progress ?? 0,
            state: state ?? "",
            size: size ?? 0,
            totalSize: totalSize ?? 0,
            downloaded: downloaded ?? 0,
            uploaded: uploaded ?? 0,
            downloadSpeed: downloadSpeed ?? 0,
            uploadSpeed: uploadSpeed ?? 0,
            eta: eta ?? -1,
            ratio: ratio ?? 0,
            category: category ?? "",
            tags: tags ?? "",
            savePath: savePath ?? "",
            addedOn: addedOn.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}
