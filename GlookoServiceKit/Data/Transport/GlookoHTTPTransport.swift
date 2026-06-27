import Foundation

public protocol GlookoHTTPTransport {

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: GlookoHTTPTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        guard let session else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            self.session = URLSession(configuration: config)
            return
        }
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GlookoAPIError.http(0) }
        return (data, http)
    }
}
