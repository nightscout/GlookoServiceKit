import Foundation

final class GlookoSocketIO: NSObject {
    private let baseURL: URL
    private let token: String
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    private var ackId = 0
    private var acks: [Int: (Any?) -> Void] = [:]
    private var connectContinuation: ((Result<Void, Error>) -> Void)?
    private var open = false
    private let lock = NSLock()

    var onClose: (() -> Void)?

    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    func connect(_ completion: @escaping (Result<Void, Error>) -> Void) {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            completion(.failure(GlookoAPIError.encoding)); return
        }
        comps.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        comps.path = "/socket.io/"
        comps.queryItems = [
            .init(name: "EIO", value: "4"),
            .init(name: "transport", value: "websocket"),
            .init(name: "token", value: token),
        ]
        guard let url = comps.url else { completion(.failure(GlookoAPIError.encoding)); return }
        connectContinuation = completion
        task = session.webSocketTask(with: url)
        task?.resume()
        receive()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    func emit(_ event: String, _ payload: Any, ack: @escaping (Any?) -> Void) {
        lock.lock(); ackId += 1; let id = ackId; acks[id] = ack; lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: [event, payload]),
              let json = String(data: data, encoding: .utf8) else { ack(nil); return }
        send("42\(id)\(json)")
    }

    private func send(_ text: String) {
        task?.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            self?.handleClosed()
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                self.handleClosed()
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receive()
            }
        }
    }

    private func handleClosed() {
        lock.lock()
        guard open || connectContinuation != nil || !acks.isEmpty else { lock.unlock(); return }
        open = false
        let pending = acks; acks.removeAll()
        let cont = connectContinuation; connectContinuation = nil
        lock.unlock()
        pending.values.forEach { $0(["error": "disconnected"]) }
        cont?(.failure(GlookoAPIError.notConnected))
        onClose?()
    }

    private func handle(_ text: String) {
        guard let first = text.first else { return }
        switch first {
        case "0":
            send("40")
        case "2":
            send("3")
        case "4":
            let body = String(text.dropFirst())
            guard let sio = body.first else { return }
            switch sio {
            case "0":
                lock.lock(); open = true; lock.unlock()
                connectContinuation?(.success(())); connectContinuation = nil
            case "3":
                handleAck(String(body.dropFirst()))
            default: break
            }
        default: break
        }
    }

    private func handleAck(_ s: String) {

        let digits = s.prefix { $0.isNumber }
        guard let id = Int(digits) else { return }
        let jsonStr = String(s.dropFirst(digits.count))
        var value: Any?
        if let d = jsonStr.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [Any] {
            value = arr.first
        }
        lock.lock(); let cb = acks.removeValue(forKey: id); lock.unlock()
        cb?(value)
    }
}

extension GlookoSocketIO: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleClosed()
    }
}
