import Foundation
import AVFoundation
import UIKit

struct JellyfinAuthenticatedIdentity: Sendable {
    let accessToken: String
    let userID: String
    let username: String
}

struct JellyfinPlaybackStream: Sendable {
    let candidates: [JellyfinPlaybackCandidate]

    var url: URL {
        candidates[0].url
    }

    var routeDescription: String {
        candidates[0].routeDescription
    }
}

struct JellyfinPlaybackCandidate: Sendable, Equatable {
    let url: URL
    let routeDescription: String
}

struct JellyfinAPIClient {
    enum APIError: LocalizedError {
        case invalidServerURL
        case invalidResponse
        case unauthorized
        case forbidden
        case missingAuthentication
        case serverMessage(String)
        case transport(URLError)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .invalidServerURL:
                return "服务器地址无效。"
            case .invalidResponse:
                return "Jellyfin 服务器返回了无法识别的响应。"
            case .unauthorized:
                return "当前 Jellyfin 会话已经失效，请重新登录。"
            case .forbidden:
                return "当前账号没有权限访问这个 Jellyfin 功能。"
            case .missingAuthentication:
                return "Jellyfin 响应里没有有效的访问令牌。"
            case let .serverMessage(message):
                return message
            case let .transport(error):
                switch error.code {
                case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                    return "无法连接到 Jellyfin 服务器，请检查地址和网络连接。"
                case .appTransportSecurityRequiresSecureConnection:
                    return "当前构建阻止了不安全的 HTTP 连接。请使用 HTTPS，或者确认你运行的是用于本地调试的 Debug 构建。"
                case .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateUntrusted, .secureConnectionFailed:
                    return "Jellyfin 服务器的 TLS 证书无法被 iOS 信任。"
                default:
                    return error.localizedDescription
                }
            case .decoding:
                return "MediaHarbor 无法解析 Jellyfin 返回的数据。"
            }
        }
    }

    private let session: URLSession
    private let deviceID: String

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session

        let key = "jellyfin.device-id"
        if let existing = defaults.string(forKey: key), existing.isEmpty == false {
            self.deviceID = existing
        } else {
            let created = UUID().uuidString
            defaults.set(created, forKey: key)
            self.deviceID = created
        }
    }

    func publicInfo(baseURL: URL) async throws -> JellyfinPublicInfo {
        let request = try makeRequest(baseURL: baseURL, path: "System/Info/Public")
        let dto: PublicSystemInfoDTO = try await send(request)

        return JellyfinPublicInfo(
            serverName: dto.serverName ?? baseURL.host ?? "Jellyfin",
            version: dto.version,
            identifier: dto.identifier,
            localAddress: dto.localAddress
        )
    }

    func authenticate(baseURL: URL, username: String, password: String) async throws -> JellyfinAuthenticatedIdentity {
        let body = AuthenticateRequestDTO(username: username, password: password)
        let request = try makeRequest(baseURL: baseURL, path: "Users/AuthenticateByName", method: "POST", body: body)
        let dto: AuthenticationResultDTO = try await send(request)

        guard let token = dto.accessToken, token.isEmpty == false else {
            throw APIError.missingAuthentication
        }

        guard let userID = dto.user?.identifier, userID.isEmpty == false else {
            throw APIError.missingAuthentication
        }

        return JellyfinAuthenticatedIdentity(
            accessToken: token,
            userID: userID,
            username: dto.user?.name ?? username
        )
    }

    func libraries(baseURL: URL, userID: String, token: String) async throws -> [JellyfinLibrary] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "UserViews",
            token: token,
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "includeHidden", value: "false"),
            ]
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asLibrary)
    }

    func consoleLibraries(baseURL: URL, userID: String, token: String) async throws -> JellyfinConsoleLibraries {
        do {
            let adminLibraries = try await administratorLibraries(baseURL: baseURL, token: token)
            return JellyfinConsoleLibraries(
                libraries: JellyfinLibrary.mediaLibraries(from: adminLibraries),
                source: .administrator
            )
        } catch let apiError as APIError where apiError.canFallbackToUserViews {
            let visibleLibraries = try await libraries(baseURL: baseURL, userID: userID, token: token)
            return JellyfinConsoleLibraries(
                libraries: JellyfinLibrary.mediaLibraries(from: visibleLibraries),
                source: .userVisible
            )
        }
    }

    func latestMovies(baseURL: URL, userID: String, token: String, limit: Int = 18) async throws -> [JellyfinMovie] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "Items/Latest",
            token: token,
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "includeItemTypes", value: "Movie"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "groupItems", value: "false"),
                URLQueryItem(name: "enableUserData", value: "true"),
            ]
        )

        let dto: [BaseItemDTO] = try await send(request)
        return dto.compactMap(\.asMovie)
    }

    func resumeItems(baseURL: URL, userID: String, token: String, limit: Int = 18) async throws -> [JellyfinLibraryItem] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "UserItems/Resume",
            token: token,
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "fields", value: "Overview,CommunityRating,ProductionYear,OfficialRating,RunTimeTicks,ImageTags,ChildCount,IndexNumber,ParentIndexNumber,UserData"),
                URLQueryItem(name: "enableUserData", value: "true"),
            ]
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asLibraryItem)
    }

    func nextUpItems(baseURL: URL, userID: String, token: String, limit: Int = 18) async throws -> [JellyfinLibraryItem] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "Shows/NextUp",
            token: token,
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "fields", value: "Overview,CommunityRating,ProductionYear,OfficialRating,RunTimeTicks,ImageTags,ChildCount,IndexNumber,ParentIndexNumber,UserData"),
                URLQueryItem(name: "enableUserData", value: "true"),
            ]
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asLibraryItem)
    }

    func favoriteItems(baseURL: URL, userID: String, token: String, limit: Int = 36) async throws -> [JellyfinLibraryItem] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "Items",
            token: token,
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "recursive", value: "true"),
                URLQueryItem(name: "isFavorite", value: "true"),
                URLQueryItem(name: "includeItemTypes", value: "Movie,Episode,Series"),
                URLQueryItem(name: "sortBy", value: "SortName"),
                URLQueryItem(name: "sortOrder", value: "Ascending"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "fields", value: "Overview,CommunityRating,ProductionYear,OfficialRating,RunTimeTicks,ImageTags,ChildCount,IndexNumber,ParentIndexNumber,UserData"),
                URLQueryItem(name: "enableUserData", value: "true"),
            ]
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asLibraryItem)
    }

    func searchItems(
        baseURL: URL,
        userID: String,
        token: String,
        searchTerm: String,
        limit: Int = 60
    ) async throws -> [JellyfinLibraryItem] {
        let trimmedSearch = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSearch.isEmpty == false else {
            return []
        }

        let request = try makeRequest(
            baseURL: baseURL,
            path: "Items",
            token: token,
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "recursive", value: "true"),
                URLQueryItem(name: "searchTerm", value: trimmedSearch),
                URLQueryItem(name: "includeItemTypes", value: "Movie,Series,Episode"),
                URLQueryItem(name: "sortBy", value: "SortName"),
                URLQueryItem(name: "sortOrder", value: "Ascending"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "fields", value: "Overview,CommunityRating,ProductionYear,OfficialRating,RunTimeTicks,ImageTags,ChildCount,IndexNumber,ParentIndexNumber,UserData"),
                URLQueryItem(name: "enableUserData", value: "true"),
            ]
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asLibraryItem)
    }

    func libraryMovies(
        baseURL: URL,
        userID: String,
        token: String,
        parentID: String,
        searchTerm: String
    ) async throws -> [JellyfinMovie] {
        var queryItems = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "parentId", value: parentID),
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "includeItemTypes", value: "Movie"),
            URLQueryItem(name: "sortBy", value: "SortName"),
            URLQueryItem(name: "sortOrder", value: "Ascending"),
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "fields", value: "Overview,CommunityRating,ProductionYear,OfficialRating,RunTimeTicks,ImageTags"),
        ]

        let trimmedSearch = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty == false {
            queryItems.append(URLQueryItem(name: "searchTerm", value: trimmedSearch))
        }

        let request = try makeRequest(
            baseURL: baseURL,
            path: "Items",
            token: token,
            queryItems: queryItems
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asMovie)
    }

    func libraryItems(
        baseURL: URL,
        userID: String,
        token: String,
        library: JellyfinLibrary,
        searchTerm: String
    ) async throws -> [JellyfinLibraryItem] {
        var queryItems = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "parentId", value: library.id),
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "sortBy", value: "SortName"),
            URLQueryItem(name: "sortOrder", value: "Ascending"),
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "fields", value: "Overview,CommunityRating,ProductionYear,OfficialRating,RunTimeTicks,ImageTags,ChildCount"),
        ]

        if let includeItemTypes = library.kind.itemTypesQueryValue {
            queryItems.append(URLQueryItem(name: "includeItemTypes", value: includeItemTypes))
        }

        let trimmedSearch = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty == false {
            queryItems.append(URLQueryItem(name: "searchTerm", value: trimmedSearch))
        }

        let request = try makeRequest(
            baseURL: baseURL,
            path: "Items",
            token: token,
            queryItems: queryItems
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asLibraryItem)
    }

    func childItems(
        baseURL: URL,
        userID: String,
        token: String,
        parentID: String,
        recursive: Bool,
        includeItemTypes: String? = nil
    ) async throws -> [JellyfinLibraryItem] {
        var queryItems = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "parentId", value: parentID),
            URLQueryItem(name: "recursive", value: recursive ? "true" : "false"),
            URLQueryItem(name: "sortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
            URLQueryItem(name: "sortOrder", value: "Ascending"),
            URLQueryItem(name: "limit", value: "400"),
            URLQueryItem(name: "fields", value: "Overview,CommunityRating,ProductionYear,OfficialRating,RunTimeTicks,ImageTags,ChildCount,IndexNumber,ParentIndexNumber,UserData"),
            URLQueryItem(name: "enableUserData", value: "true"),
        ]

        if let includeItemTypes, includeItemTypes.isEmpty == false {
            queryItems.append(URLQueryItem(name: "includeItemTypes", value: includeItemTypes))
        }

        let request = try makeRequest(
            baseURL: baseURL,
            path: "Items",
            token: token,
            queryItems: queryItems
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asLibraryItem)
    }

    func scheduledTasks(baseURL: URL, token: String) async throws -> [JellyfinTask] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "ScheduledTasks",
            token: token,
            queryItems: [
                URLQueryItem(name: "isHidden", value: "false"),
            ]
        )

        let dto: [ScheduledTaskDTO] = try await send(request)
        return dto.map(\.asTask).sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func startLibraryScan(baseURL: URL, token: String) async throws {
        let request = try makeRequest(baseURL: baseURL, path: "Library/Refresh", method: "POST", token: token)
        try await sendVoid(request)
    }

    func refreshLibraryItem(baseURL: URL, token: String, itemID: String) async throws {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "Items/\(itemID)/Refresh",
            method: "POST",
            token: token,
            queryItems: [
                URLQueryItem(name: "metadataRefreshMode", value: "Default"),
                URLQueryItem(name: "imageRefreshMode", value: "None"),
                URLQueryItem(name: "replaceAllMetadata", value: "false"),
                URLQueryItem(name: "replaceAllImages", value: "false"),
            ]
        )
        try await sendVoid(request)
    }

    private func administratorLibraries(baseURL: URL, token: String) async throws -> [JellyfinLibrary] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "Library/VirtualFolders",
            token: token
        )

        do {
            let dto: [VirtualFolderDTO] = try await send(request)
            let libraries = dto.compactMap(\.asLibrary)
            if libraries.isEmpty == false {
                return libraries
            }
        } catch let apiError as APIError where apiError.canFallbackToMediaFolders {
            return try await administratorMediaFolders(baseURL: baseURL, token: token)
        }

        return try await administratorMediaFolders(baseURL: baseURL, token: token)
    }

    private func administratorMediaFolders(baseURL: URL, token: String) async throws -> [JellyfinLibrary] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "Library/MediaFolders",
            token: token
        )

        let dto: BaseItemQueryResultDTO = try await send(request)
        return dto.items.compactMap(\.asLibrary)
    }

    func primaryImageURL(
        baseURL: URL,
        itemID: String,
        token: String,
        tag: String?,
        maxWidth: Int,
        maxHeight: Int
    ) -> URL? {
        let endpoint = baseURL.appendingPathComponent("Items/\(itemID)/Images/Primary")

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = [
            URLQueryItem(name: "api_key", value: token),
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "maxHeight", value: String(maxHeight)),
            URLQueryItem(name: "quality", value: "90"),
        ]

        if let tag, tag.isEmpty == false {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }

        components.queryItems = queryItems
        return components.url
    }

    func webDetailsURL(baseURL: URL, itemID: String) -> URL? {
        let endpoint = baseURL.appendingPathComponent("web/index.html")

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.fragment = "/details?id=\(itemID)"
        return components.url
    }

    func directVideoURL(
        baseURL: URL,
        itemID: String,
        token: String,
        playSessionID: String? = nil,
        mediaSourceID: String? = nil,
        tag: String? = nil
    ) -> URL? {
        let endpoint = baseURL.appendingPathComponent("Videos/\(itemID)/stream")

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: token),
        ]

        if let playSessionID, playSessionID.isEmpty == false {
            queryItems.append(URLQueryItem(name: "playSessionId", value: playSessionID))
        }
        if let mediaSourceID, mediaSourceID.isEmpty == false {
            queryItems.append(URLQueryItem(name: "mediaSourceId", value: mediaSourceID))
        }
        if let tag, tag.isEmpty == false {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }

        components.queryItems = queryItems
        return components.url
    }

    func playbackStream(
        baseURL: URL,
        userID: String,
        token: String,
        itemID: String
    ) async throws -> JellyfinPlaybackStream {
        let requestBody = PlaybackInfoRequestDTO(
            userID: userID,
            maxStreamingBitrate: 60_000_000,
            deviceProfile: .mediaHarborDefault
        )

        let request = try makeRequest(
            baseURL: baseURL,
            path: "Items/\(itemID)/PlaybackInfo",
            method: "POST",
            token: token,
            body: requestBody
        )

        let response: PlaybackInfoResponseDTO = try await send(request)
        let playSessionID = response.playSessionID
        let mediaSources = response.mediaSources ?? []
        let selectedSource = mediaSources.first
        var candidates: [JellyfinPlaybackCandidate] = []

        func appendCandidate(url: URL?, routeDescription: String) {
            guard let url else {
                return
            }

            if candidates.contains(where: { $0.url == url }) == false {
                candidates.append(
                    JellyfinPlaybackCandidate(url: url, routeDescription: routeDescription)
                )
            }
        }

        if selectedSource?.supportsDirectStream == true,
           let directStreamURL = selectedSource?.directStreamURL,
           let resolvedURL = resolvePlaybackURL(baseURL: baseURL, token: token, pathOrURL: directStreamURL)
        {
            appendCandidate(url: resolvedURL, routeDescription: "直接串流")
        }

        let directURL = directVideoURL(
            baseURL: baseURL,
            itemID: itemID,
            token: token,
            playSessionID: playSessionID,
            mediaSourceID: selectedSource?.id ?? itemID,
            tag: selectedSource?.eTag
        )

        if selectedSource?.supportsDirectPlay == true {
            appendCandidate(url: directURL, routeDescription: "直接播放")
        }

        if let transcodingURL = selectedSource?.transcodingURL,
           let resolvedURL = resolvePlaybackURL(baseURL: baseURL, token: token, pathOrURL: transcodingURL)
        {
            appendCandidate(url: resolvedURL, routeDescription: "服务器转码")
        }

        appendCandidate(url: directURL, routeDescription: "直接播放")

        if candidates.isEmpty == false {
            return JellyfinPlaybackStream(candidates: candidates)
        }

        throw APIError.serverMessage("Jellyfin 没有返回可用的播放地址。")
    }

    func startTask(baseURL: URL, token: String, taskID: String) async throws {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "ScheduledTasks/Running/\(taskID)",
            method: "POST",
            token: token
        )
        try await sendVoid(request)
    }

    func stopTask(baseURL: URL, token: String, taskID: String) async throws {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "ScheduledTasks/Running/\(taskID)",
            method: "DELETE",
            token: token
        )
        try await sendVoid(request)
    }

    func setFavorite(
        baseURL: URL,
        userID: String,
        token: String,
        itemID: String,
        isFavorite: Bool
    ) async throws {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "UserFavoriteItems/\(itemID)",
            method: isFavorite ? "POST" : "DELETE",
            token: token,
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
            ]
        )
        try await sendVoid(request)
    }

    private func makeRequest<T: Encodable>(
        baseURL: URL,
        path: String,
        method: String = "GET",
        token: String? = nil,
        queryItems: [URLQueryItem] = [],
        body: T
    ) throws -> URLRequest {
        let data = try JSONEncoder().encode(body)
        return try makeRequest(baseURL: baseURL, path: path, method: method, token: token, queryItems: queryItems, bodyData: data)
    }

    private func makeRequest(
        baseURL: URL,
        path: String,
        method: String = "GET",
        token: String? = nil,
        queryItems: [URLQueryItem] = [],
        bodyData: Data? = nil
    ) throws -> URLRequest {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let endpoint = baseURL.appendingPathComponent(trimmedPath)

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidServerURL
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw APIError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorizationHeader(token: token), forHTTPHeaderField: "Authorization")

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            break
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        default:
            if let message = String(data: data, encoding: .utf8), message.isEmpty == false {
                throw APIError.serverMessage(message)
            }

            throw APIError.invalidResponse
        }
    }

    private func authorizationHeader(token: String?) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let client = "MediaHarbor"
        let device = UIDevice.current.model.replacingOccurrences(of: "\"", with: "")

        var values = [
            "Client=\"\(client)\"",
            "Device=\"\(device)\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(version)\"",
        ]

        if let token, token.isEmpty == false {
            values.append("Token=\"\(token)\"")
        }

        return "MediaBrowser \(values.joined(separator: ", "))"
    }

    private func resolvePlaybackURL(baseURL: URL, token: String, pathOrURL: String) -> URL? {
        if let fullURL = URL(string: pathOrURL), fullURL.scheme != nil {
            return fullURL
        }

        let trimmed = pathOrURL.hasPrefix("/") ? String(pathOrURL.dropFirst()) : pathOrURL
        guard let joined = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }

        guard var components = URLComponents(url: joined, resolvingAgainstBaseURL: false) else {
            return joined
        }

        var queryItems = components.queryItems ?? []
        if queryItems.contains(where: { $0.name == "api_key" }) == false {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        components.queryItems = queryItems
        return components.url
    }
}

extension JellyfinAPIClient.APIError {
    var isGenericServerProcessingMessage: Bool {
        guard case let .serverMessage(message) = self else {
            return false
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "error processing request."
    }
}

private struct AuthenticateRequestDTO: Encodable {
    let username: String
    let password: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case password = "Pw"
    }
}

private struct PublicSystemInfoDTO: Decodable {
    let serverName: String?
    let version: String?
    let identifier: String?
    let localAddress: String?

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case identifier = "Id"
        case localAddress = "LocalAddress"
    }
}

private struct AuthenticationResultDTO: Decodable {
    let user: UserDTO?
    let accessToken: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
    }
}

private struct PlaybackInfoRequestDTO: Encodable {
    let userID: String
    let maxStreamingBitrate: Int
    let deviceProfile: PlaybackDeviceProfileDTO

    enum CodingKeys: String, CodingKey {
        case userID = "UserId"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case deviceProfile = "DeviceProfile"
    }
}

private struct PlaybackDeviceProfileDTO: Encodable {
    let name: String
    let directPlayProfiles: [PlaybackDirectPlayProfileDTO]
    let transcodingProfiles: [PlaybackTranscodingProfileDTO]
    let subtitleProfiles: [PlaybackSubtitleProfileDTO]
    let codecProfiles: [PlaybackCodecProfileDTO]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case directPlayProfiles = "DirectPlayProfiles"
        case transcodingProfiles = "TranscodingProfiles"
        case subtitleProfiles = "SubtitleProfiles"
        case codecProfiles = "CodecProfiles"
    }

    static let mediaHarborDefault = PlaybackDeviceProfileDTO(
        name: "MediaHarbor",
        directPlayProfiles: [
            PlaybackDirectPlayProfileDTO(
                container: "mp4,m4v,mov,mkv,webm,avi,ts,m2ts",
                type: "Video",
                videoCodec: "h264,hevc,av1,vp8,vp9,mpeg4,mpeg2video,vc1,prores,dirac,dv,ffv1,flv1,h261,h263,mjpeg,msmpeg4v1,msmpeg4v2,msmpeg4v3,theora,wmv1,wmv2,wmv3",
                audioCodec: "aac,ac3,alac,amr_nb,amr_wb,dts,eac3,flac,mp1,mp2,mp3,nellymoser,opus,pcm_alaw,pcm_bluray,pcm_dvd,pcm_mulaw,pcm_s16be,pcm_s16le,pcm_s24be,pcm_s24le,pcm_u8,speex,vorbis,wavpack,wmalossless,wmapro,wmav1,wmav2"
            ),
        ],
        transcodingProfiles: [
            PlaybackTranscodingProfileDTO(
                container: "mp4",
                type: "Video",
                protocolName: "hls",
                videoCodec: "h264",
                audioCodec: "aac",
                context: "Streaming",
                maxAudioChannels: "8",
                minSegments: 2,
                breakOnNonKeyFrames: true,
                enableSubtitlesInManifest: true
            ),
        ],
        subtitleProfiles: [
            PlaybackSubtitleProfileDTO(format: "vtt", method: "Hls"),
        ],
        codecProfiles: PlaybackCodecProfileDTO.mediaHarborDefault
    )
}

private struct PlaybackDirectPlayProfileDTO: Encodable {
    let container: String
    let type: String
    let videoCodec: String
    let audioCodec: String

    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case type = "Type"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
    }
}

private struct PlaybackTranscodingProfileDTO: Encodable {
    let container: String
    let type: String
    let protocolName: String
    let videoCodec: String
    let audioCodec: String
    let context: String
    let maxAudioChannels: String
    let minSegments: Int
    let breakOnNonKeyFrames: Bool
    let enableSubtitlesInManifest: Bool

    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case type = "Type"
        case protocolName = "Protocol"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
        case context = "Context"
        case maxAudioChannels = "MaxAudioChannels"
        case minSegments = "MinSegments"
        case breakOnNonKeyFrames = "BreakOnNonKeyFrames"
        case enableSubtitlesInManifest = "EnableSubtitlesInManifest"
    }
}

private struct PlaybackSubtitleProfileDTO: Encodable {
    let format: String
    let method: String

    enum CodingKeys: String, CodingKey {
        case format = "Format"
        case method = "Method"
    }
}

private struct PlaybackInfoResponseDTO: Decodable {
    let mediaSources: [PlaybackMediaSourceDTO]?
    let playSessionID: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionID = "PlaySessionId"
    }
}

private struct PlaybackMediaSourceDTO: Decodable {
    let id: String?
    let eTag: String?
    let transcodingURL: String?
    let directStreamURL: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case eTag = "ETag"
        case transcodingURL = "TranscodingUrl"
        case directStreamURL = "DirectStreamUrl"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
    }
}

private struct PlaybackCodecProfileDTO: Encodable {
    let codec: String
    let type: String
    let conditions: [PlaybackProfileConditionDTO]

    enum CodingKeys: String, CodingKey {
        case codec = "Codec"
        case type = "Type"
        case conditions = "Conditions"
    }

    static let mediaHarborDefault: [PlaybackCodecProfileDTO] = [
        PlaybackCodecProfileDTO(
            codec: "h264",
            type: "Video",
            conditions: PlaybackProfileConditionDTO.h264Base + [
                PlaybackProfileConditionDTO(
                    condition: "EqualsAny",
                    isRequired: false,
                    property: "VideoRangeType",
                    value: "SDR|DOVIWithSDR"
                ),
            ]
        ),
        PlaybackCodecProfileDTO(
            codec: "hevc",
            type: "Video",
            conditions: PlaybackProfileConditionDTO.hevcBase + [
                PlaybackProfileConditionDTO(
                    condition: "EqualsAny",
                    isRequired: false,
                    property: "VideoRangeType",
                    value: "SDR|HLG|HDR10|HDR10Plus|DOVIWithSDR|DOVIWithHLG|DOVIWithHDR10|DOVIWithHDR10Plus|DOVIWithELHDR10Plus"
                ),
            ]
        ),
    ]
}

private struct PlaybackProfileConditionDTO: Encodable {
    let condition: String
    let isRequired: Bool
    let property: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case condition = "Condition"
        case isRequired = "IsRequired"
        case property = "Property"
        case value = "Value"
    }

    static let h264Base: [PlaybackProfileConditionDTO] = [
        PlaybackProfileConditionDTO(condition: "NotEquals", isRequired: false, property: "IsAnamorphic", value: "true"),
        PlaybackProfileConditionDTO(condition: "EqualsAny", isRequired: false, property: "VideoProfile", value: "high|main|baseline|constrained baseline"),
        PlaybackProfileConditionDTO(condition: "LessThanEqual", isRequired: false, property: "VideoLevel", value: "80"),
        PlaybackProfileConditionDTO(condition: "NotEquals", isRequired: false, property: "IsInterlaced", value: "true"),
    ]

    static let hevcBase: [PlaybackProfileConditionDTO] = [
        PlaybackProfileConditionDTO(condition: "NotEquals", isRequired: false, property: "IsAnamorphic", value: "true"),
        PlaybackProfileConditionDTO(condition: "EqualsAny", isRequired: false, property: "VideoProfile", value: "main|main 10"),
        PlaybackProfileConditionDTO(condition: "LessThanEqual", isRequired: false, property: "VideoLevel", value: "175"),
        PlaybackProfileConditionDTO(condition: "NotEquals", isRequired: false, property: "IsInterlaced", value: "true"),
    ]

}

private struct UserDTO: Decodable {
    let identifier: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case identifier = "Id"
        case name = "Name"
    }
}

private struct BaseItemQueryResultDTO: Decodable {
    let items: [BaseItemDTO]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

private struct VirtualFolderDTO: Decodable {
    let name: String?
    let itemID: String?
    let collectionType: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case itemID = "ItemId"
        case collectionType = "CollectionType"
    }

    var asLibrary: JellyfinLibrary? {
        guard let itemID, let name else {
            return nil
        }

        return JellyfinLibrary(
            id: itemID,
            name: name,
            collectionType: collectionType,
            itemCount: nil,
            type: "CollectionFolder",
            isFolder: true
        )
    }
}

private struct BaseItemDTO: Decodable {
    let identifier: String?
    let name: String?
    let type: String?
    let collectionType: String?
    let recursiveItemCount: Int?
    let childCount: Int?
    let isFolder: Bool?
    let overview: String?
    let productionYear: Int?
    let communityRating: Double?
    let officialRating: String?
    let runtimeTicks: Int64?
    let premiereDateText: String?
    let imageTags: [String: String]?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let userData: UserDataDTO?

    enum CodingKeys: String, CodingKey {
        case identifier = "Id"
        case name = "Name"
        case type = "Type"
        case collectionType = "CollectionType"
        case recursiveItemCount = "RecursiveItemCount"
        case childCount = "ChildCount"
        case isFolder = "IsFolder"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case communityRating = "CommunityRating"
        case officialRating = "OfficialRating"
        case runtimeTicks = "RunTimeTicks"
        case premiereDateText = "PremiereDate"
        case imageTags = "ImageTags"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case userData = "UserData"
    }

    var asLibrary: JellyfinLibrary? {
        guard let identifier, let name else {
            return nil
        }

        return JellyfinLibrary(
            id: identifier,
            name: name,
            collectionType: collectionType,
            itemCount: recursiveItemCount ?? childCount,
            type: type,
            isFolder: isFolder ?? false
        )
    }

    var asMovie: JellyfinMovie? {
        guard let identifier, let name else {
            return nil
        }

        return JellyfinMovie(
            id: identifier,
            name: name,
            overview: overview,
            productionYear: productionYear,
            communityRating: communityRating,
            officialRating: officialRating,
            runtimeTicks: runtimeTicks,
            premiereDateText: premiereDateText,
            primaryImageTag: imageTags?["Primary"],
            playbackPositionTicks: userData?.playbackPositionTicks,
            isFavorite: userData?.isFavorite ?? false
        )
    }

    var asLibraryItem: JellyfinLibraryItem? {
        guard let identifier, let name else {
            return nil
        }

        return JellyfinLibraryItem(
            id: identifier,
            name: name,
            type: type,
            overview: overview,
            productionYear: productionYear,
            communityRating: communityRating,
            officialRating: officialRating,
            runtimeTicks: runtimeTicks,
            premiereDateText: premiereDateText,
            primaryImageTag: imageTags?["Primary"],
            childCount: childCount,
            isFolder: isFolder ?? false,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber,
            playbackPositionTicks: userData?.playbackPositionTicks,
            isFavorite: userData?.isFavorite ?? false
        )
    }
}

private struct UserDataDTO: Decodable {
    let playbackPositionTicks: Int64?
    let isFavorite: Bool?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case isFavorite = "IsFavorite"
    }
}

private struct ScheduledTaskDTO: Decodable {
    let id: String?
    let name: String?
    let state: JellyfinTaskState?
    let currentProgressPercentage: Double?
    let description: String?
    let category: String?
    let key: String?
    let lastExecutionResult: TaskResultDTO?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case state = "State"
        case currentProgressPercentage = "CurrentProgressPercentage"
        case description = "Description"
        case category = "Category"
        case key = "Key"
        case lastExecutionResult = "LastExecutionResult"
    }

    var asTask: JellyfinTask {
        JellyfinTask(
            id: id ?? UUID().uuidString,
            name: name ?? "未命名任务",
            state: state ?? .idle,
            progress: currentProgressPercentage,
            category: category,
            key: key,
            summary: description,
            lastRunDateText: lastExecutionResult?.endTimeUTC,
            lastRunStatus: lastExecutionResult?.status
        )
    }
}

private struct TaskResultDTO: Decodable {
    let endTimeUTC: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case endTimeUTC = "EndTimeUtc"
        case status = "Status"
    }
}

private extension JellyfinAPIClient.APIError {
    var canFallbackToUserViews: Bool {
        switch self {
        case .forbidden:
            return true
        case .invalidResponse:
            return true
        case let .serverMessage(message):
            let lowered = message.lowercased()
            return lowered.contains("not found") || lowered.contains("404")
        default:
            return false
        }
    }

    var canFallbackToMediaFolders: Bool {
        switch self {
        case .invalidResponse:
            return true
        case let .serverMessage(message):
            let lowered = message.lowercased()
            return lowered.contains("not found") || lowered.contains("404")
        default:
            return false
        }
    }
}
