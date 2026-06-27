import Foundation
import XCTest
@testable import GlookoServiceKit

final class MockHTTPTransport: GlookoHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var handler: (URLRequest, Int) throws -> (Data, HTTPURLResponse)
    private var callIndex = 0

    init(handler: @escaping (URLRequest, Int) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        defer { callIndex += 1 }
        return try handler(request, callIndex)
    }

    var lastBody: Data? { requests.last?.httpBody }
    func bodyJSON(at index: Int) -> [String: Any]? {
        guard index < requests.count, let body = requests[index].httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return object
    }

    var paths: [String] { requests.compactMap { $0.url?.path } }

    func json(forPath path: String) -> [String: Any]? {
        guard let request = requests.first(where: { $0.url?.path == path }), let body = request.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return object
    }
}

enum MockResponder {

    static func response(_ request: URLRequest, status: Int, setCookie: String? = nil) throws -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let setCookie { headers["Set-Cookie"] = setCookie }
        let url = try XCTUnwrap(request.url)
        return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    }

    static func ok(_ request: URLRequest, body: Data = Data(), setCookie: String? = nil) throws -> (Data, HTTPURLResponse) {
        (body, try response(request, status: 200, setCookie: setCookie))
    }

    static func status(_ request: URLRequest, _ code: Int, body: Data = Data()) throws -> (Data, HTTPURLResponse) {
        (body, try response(request, status: code))
    }
}
