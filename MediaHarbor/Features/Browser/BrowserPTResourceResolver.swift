import Foundation

struct BrowserPTResourceResolver {
    enum ResolverError: LocalizedError {
        case invalidDownloadURL
        case missingTorrentID
        case missingAPIToken
        case serverMessage(String)

        var errorDescription: String? {
            switch self {
            case .invalidDownloadURL:
                return "没有拿到可用的下载地址。"
            case .missingTorrentID:
                return "当前条目只识别到了详情入口，暂时不能直接投递到 qBittorrent。"
            case .missingAPIToken:
                return "M-Team 需要先在浏览器设置里填写 API Token。"
            case let .serverMessage(message):
                return message
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolveDownloadURL(
        for resource: BrowserResource,
        site: BrowserSite,
        credential: BrowserCredential
    ) async throws -> URL {
        if let downloadURLString = resource.downloadURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
           downloadURLString.isEmpty == false,
           let url = URL(string: downloadURLString) {
            return url
        }

        switch site.kind {
        case .mTeam:
            return try await resolveMTeamDownloadURL(for: resource, site: site, apiToken: credential.trimmedAPIToken)
        default:
            throw ResolverError.invalidDownloadURL
        }
    }

    func extractTorrentID(from resource: BrowserResource) -> String? {
        if let torrentID = resource.torrentID?.trimmingCharacters(in: .whitespacesAndNewlines),
           torrentID.isEmpty == false {
            return torrentID
        }

        let candidates = [
            resource.detailsURLString,
            resource.downloadURLString,
        ]

        for candidate in candidates {
            if let torrentID = extractTorrentID(from: candidate) {
                return torrentID
            }
        }

        return nil
    }

    private func resolveMTeamDownloadURL(for resource: BrowserResource, site: BrowserSite, apiToken: String) async throws -> URL {
        guard apiToken.isEmpty == false else {
            throw ResolverError.missingAPIToken
        }

        guard let torrentID = extractTorrentID(from: resource) else {
            throw ResolverError.missingTorrentID
        }

        guard let originURL = site.normalizedHomeURL,
              var components = URLComponents(url: originURL, resolvingAgainstBaseURL: false),
              let host = components.host else {
            throw ResolverError.invalidDownloadURL
        }

        let hostComponents = host.split(separator: ".")
        if hostComponents.count >= 3 {
            components.host = (["api"] + hostComponents.dropFirst()).joined(separator: ".")
        }

        components.path = "/api/torrent/genDlToken"
        components.query = nil
        components.fragment = nil

        guard let requestURL = components.url else {
            throw ResolverError.invalidDownloadURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiToken, forHTTPHeaderField: "x-api-key")
        request.setValue(originURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(originURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = multipartBody(fieldName: "id", value: torrentID, boundary: boundary)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResolverError.serverMessage("M-Team 返回了无法识别的响应。")
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "M-Team 生成下载地址失败。"
            throw ResolverError.serverMessage(message)
        }

        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (payload?["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard message.isEmpty || message.caseInsensitiveCompare("SUCCESS") == .orderedSame else {
            throw ResolverError.serverMessage(message)
        }

        if let dataString = payload?["data"] as? String,
           let url = URL(string: dataString, relativeTo: originURL)?.absoluteURL {
            return url
        }

        if let dataPayload = payload?["data"] as? [String: Any],
           let dataString = dataPayload["url"] as? String,
           let url = URL(string: dataString, relativeTo: originURL)?.absoluteURL {
            return url
        }

        throw ResolverError.invalidDownloadURL
    }

    private func extractTorrentID(from candidate: String?) -> String? {
        guard let candidate,
              candidate.isEmpty == false else {
            return nil
        }

        let patterns = [
            #"(?:^|[/?])details?\.php\?[^#]*\bid=(\d+)"#,
            #"/detail/(\d+)"#,
            #"#/detail\?[^#]*\bid=(\d+)"#,
            #"#/(\d+)(?:\?.*)?$"#,
            #"(?:^|[/?])download(?:_notice)?\.php\?[^#]*\bid=(\d+)"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)),
               let range = Range(match.range(at: 1), in: candidate) {
                return String(candidate[range])
            }
        }

        return nil
    }

    private func multipartBody(fieldName: String, value: String, boundary: String) -> Data {
        var body = Data()
        let lines = [
            "--\(boundary)",
            "Content-Disposition: form-data; name=\"\(fieldName)\"",
            "",
            value,
            "--\(boundary)--",
            "",
        ]

        for line in lines {
            body.append(line.data(using: .utf8) ?? Data())
            body.append(Data([0x0D, 0x0A]))
        }

        return body
    }
}
