import Foundation

enum LocalBridge {
    static let port: UInt16 = 49213
    static let origin = "http://127.0.0.1:49213"
}

struct BridgeUpdate: Codable {
    var text: String?
    var videoAt: Date?
    var audioAt: Date?
    var speechStatus: String?
}
struct BridgeCommand: Codable {
    var paused = false
    var stop = false
    var appVisible = true
}
struct BridgeReply: Codable {
    var ok: Bool
    var message = ""
    var token: String?
    var settings: AppSettings?
    var command: BridgeCommand?
}

/// A per-session, one-use code authorizes exactly one extension. No fixed shared secret.
struct PairingGate {
    private let code: String
    private let token: String
    private let createdAt: TimeInterval
    private(set) var attempts = 0
    private(set) var paired = false
    private(set) var invalidated = false
    init(code: String, token: String, now: TimeInterval) {
        self.code = code; self.token = token; createdAt = now
    }
    mutating func pair(code supplied: String, now: TimeInterval) -> String? {
        guard !invalidated, !paired, attempts < 5, now - createdAt < 120 else { return nil }
        attempts += 1
        guard supplied.count == 6, Self.same(supplied, code) else { return nil }
        paired = true
        return token
    }
    func accepts(_ supplied: String, now: TimeInterval) -> Bool {
        !invalidated && paired && now - createdAt < 1800 && Self.same(supplied, token)
    }
    mutating func invalidate() { invalidated = true }
    private static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var difference: UInt8 = 0
        for i in x.indices { difference |= x[i] ^ y[i] }
        return difference == 0
    }
}

struct BridgeHTTPRequest {
    let path: String
    let token: String
    let body: Data
    enum Parsing { case incomplete, rejected, complete(BridgeHTTPRequest) }
    static func parse(_ data: Data) -> Parsing {
        guard data.count <= 16_384 else { return .rejected }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 4096 ? .rejected : .incomplete
        }
        guard boundary.lowerBound < 4096,
              let headers = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return .rejected }
        let lines = headers.components(separatedBy: "\r\n")
        guard let first = lines.first else { return .rejected }
        let pieces = first.split(separator: " ")
        guard pieces.count == 3, pieces[0] == "POST", pieces[2] == "HTTP/1.1",
              ["/pair", "/update", "/finish"].contains(String(pieces[1])) else { return .rejected }
        var length: Int?
        var token = ""
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .rejected }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "transfer-encoding" { return .rejected }
            if name == "content-length" {
                guard length == nil, let size = Int(value), size >= 0, size <= 8192 else { return .rejected }
                length = size
            }
            if name == "authorization" {
                guard token.isEmpty, value.hasPrefix("Bearer ") else { return .rejected }
                token = String(value.dropFirst(7))
            }
        }
        guard let size = length else { return .rejected }
        let start = boundary.upperBound
        guard data.count >= start + size else { return .incomplete }
        guard data.count == start + size else { return .rejected }
        return .complete(BridgeHTTPRequest(path: String(pieces[1]), token: token, body: Data(data[start...])))
    }
}
