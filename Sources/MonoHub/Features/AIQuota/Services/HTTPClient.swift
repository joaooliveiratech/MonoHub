import Foundation

nonisolated struct HTTPClient: Sendable {
    enum Failure: Error {
        case notHTTP
        case payloadTooLarge
    }

    static let maximumPayloadBytes = 512 * 1024
    static let shared = HTTPClient(timeout: 8.0, resourceTimeout: 10.0)

    private let session: URLSession

    func data(for request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        try await send(request)
    }

    init(timeout: TimeInterval, resourceTimeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        guard data.count <= Self.maximumPayloadBytes else { throw Failure.payloadTooLarge }
        return (data, http)
    }
}

nonisolated extension URLRequest {
    static func get(
        _ url: URL,
        timeout: TimeInterval = 15,
        bearer: String? = nil,
        userAgent: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        if let bearer {
            request.setBearer(bearer)
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        return request
    }

    static func postJSON(_ url: URL, body: Data, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    mutating func setBearer(_ token: String) {
        setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
