import Foundation
import Network

/// Bound exclusively to 127.0.0.1. It exposes no API keys, screenshots, or transcript-read route.
final class LocalHTTPServer {
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private let handle: (BridgeHTTPRequest) -> BridgeReply
    init(queue: DispatchQueue, handle: @escaping (BridgeHTTPRequest) -> BridgeReply) {
        self.queue = queue; self.handle = handle
    }
    func start(completion: @escaping (Bool) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: LocalBridge.port)!)
        parameters.requiredInterfaceType = .loopback
        parameters.includePeerToPeer = false
        let listener = try NWListener(using: parameters)
        self.listener = listener
        var notified = false
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !notified { notified = true; completion(true) }
            case .failed:
                if !notified { notified = true; completion(false) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self, self.connections.count < 8 else { connection.cancel(); return }
            let id = UUID()
            self.connections[id] = connection
            connection.stateUpdateHandler = { [weak self] state in
                switch state { case .cancelled, .failed: self?.connections.removeValue(forKey: id)
                default: break }
            }
            connection.start(queue: self.queue)
            self.receive(connection, data: Data())
            self.queue.asyncAfter(deadline: .now() + 4) { [weak connection] in connection?.cancel() }
        }
        listener.start(queue: queue)
    }
    func stop() {
        listener?.cancel(); listener = nil
        let open = Array(connections.values); connections.removeAll()
        open.forEach { $0.cancel() }
    }
    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, done, error in
            guard let self = self else { connection.cancel(); return }
            var bytes = data
            if let chunk = chunk { bytes.append(chunk) }
            switch BridgeHTTPRequest.parse(bytes) {
            case .complete(let request): self.reply(connection, value: self.handle(request), status: "200 OK")
            case .rejected:
                self.reply(connection, value: BridgeReply(ok: false, message: "Yêu cầu cục bộ không hợp lệ."), status: "400 Bad Request")
            case .incomplete:
                if done || error != nil { connection.cancel() }
                else { self.receive(connection, data: bytes) }
            }
        }
    }
    private func reply(_ connection: NWConnection, value: BridgeReply, status: String) {
        let body = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        var data = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}
