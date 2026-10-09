import Foundation
import CryptoKit
import UIKit

struct BSendOnlineSession: Decodable {
    let room: String
    let expiresAt: Int64
    let ownerWebSocketURL: String
    let guestURL: String
}

@MainActor
final class BSendOnlineModel: ObservableObject {
    static let maximumFileSize = 50 * 1024 * 1024
    static let relay = "https://bachsend-relay.mrbach222.workers.dev"

    @Published private(set) var shareURL: String?
    @Published private(set) var connected = false
    @Published private(set) var peerOnline = false
    @Published private(set) var connecting = false
    @Published private(set) var busy = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressTitle: String = ""
    @Published var message = "Nhấn Tạo link Online để ghép nối PC ở mạng khác."
    @Published private(set) var expiry: Date?

    private var socket: URLSessionWebSocketTask?
    private var ownerURL: URL?
    private var receivingTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var sessionMarker = UUID()
    private var sharedKey: SymmetricKey?
    private var incomingFile: FileHandle?
    private var incomingTemporary: URL?
    private var incomingID: String?
    private var incomingName = ""
    private var incomingExpected: Int64 = 0
    private var incomingReceived: Int64 = 0
    private var awaitingReceipt: String?
    private var acknowledgedReceipt: String?
    var didReceive: (() -> Void)?

    var isActive: Bool { connected || connecting }
    var maySend: Bool { connected && peerOnline && !busy }
    var canClose: Bool { connected || connecting || shareURL != nil }

    func start() {
        guard !isActive else { return }
        stop(clearStatus: false)
        connecting = true
        message = "Đang tạo phiên truyền file trên Cloudflare..."
        let marker = sessionMarker
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = URL(string: Self.relay + "/api/session") else {
                    throw NSError(domain: "BSend", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Địa chỉ relay không hợp lệ."
                    ])
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data("{}".utf8)
                request.timeoutInterval = 20
                let (body, response) = try await URLSession.shared.data(for: request)
                guard marker == self.sessionMarker else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                    throw NSError(domain: "BSend", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Máy chủ chưa tạo được phiên. Hãy kiểm tra Workers / Durable Objects."
                    ])
                }
                let session = try JSONDecoder().decode(BSendOnlineSession.self, from: body)
                guard let owner = URL(string: session.ownerWebSocketURL),
                      owner.scheme == "wss", owner.host == "bachsend-relay.mrbach222.workers.dev" else {
                    throw NSError(domain: "BSend", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Đường dẫn WebSocket không hợp lệ."
                    ])
                }
                let key = SymmetricKey(size: .bits256)
                let rawKey = key.withUnsafeBytes { Data($0) }
                let hex = rawKey.map { String(format: "%02x", $0) }.joined()
                self.sharedKey = key
                self.shareURL = session.guestURL + "." + hex
                self.expiry = Date(timeIntervalSince1970: TimeInterval(session.expiresAt) / 1000)
                self.ownerURL = owner
                self.connectSocket(owner, marker: marker)
            } catch {
                guard marker == self.sessionMarker else { return }
                self.stop(clearStatus: false)
                self.message = "Không mở được Online: \(error.localizedDescription)"
            }
        }
    }

    func stop() { stop(clearStatus: true) }

    // Keep the pairing URL and key while iOS switches apps. A dormant iOS app
    // cannot reliably keep a live socket; reconnect when it becomes foreground.
    func pauseForBackground() {
        guard ownerURL != nil, shareURL != nil else { return }
        sessionMarker = UUID()
        uploadTask?.cancel()
        uploadTask = nil
        receivingTask?.cancel()
        receivingTask = nil
        pingTask?.cancel()
        pingTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        cleanupIncoming()
        connecting = false
        connected = false
        peerOnline = false
        busy = false
        progress = 0
        progressTitle = ""
        awaitingReceipt = nil
        acknowledgedReceipt = nil
        message = "Đã tạm dừng trong nền. Quay lại B Send để kết nối tiếp."
    }

    func resumeAfterBackground() {
        guard let ownerURL, shareURL != nil, !connected, !connecting else { return }
        if let expiry, Date() >= expiry {
            stop(clearStatus: false)
            message = "Link Online đã hết hạn. Tạo phiên mới."
            return
        }
        connecting = true
        message = "Đang kết nối lại phiên Online..."
        connectSocket(ownerURL, marker: sessionMarker)
    }

    private func connectSocket(_ owner: URL, marker: UUID) {
        guard marker == sessionMarker else { return }
        let ws = URLSession.shared.webSocketTask(with: owner)
        socket = ws
        ws.resume()
        message = "Đang kết nối WebSocket bảo mật..."
        receivingTask = Task { [weak self] in
            await self?.listen(marker: marker)
        }
        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && marker == self.sessionMarker {
                try? await Task.sleep(for: .seconds(22))
                guard !Task.isCancelled, marker == self.sessionMarker else { break }
                ws.sendPing { _ in }
            }
        }
    }

    private func stop(clearStatus: Bool) {
        sessionMarker = UUID()
        uploadTask?.cancel()
        uploadTask = nil
        receivingTask?.cancel()
        receivingTask = nil
        pingTask?.cancel()
        pingTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        ownerURL = nil
        cleanupIncoming()
        sharedKey = nil
        shareURL = nil
        expiry = nil
        connecting = false
        connected = false
        peerOnline = false
        busy = false
        progress = 0
        progressTitle = ""
        awaitingReceipt = nil
        acknowledgedReceipt = nil
        if clearStatus { message = "Phiên Online đã đóng. Link cũ không dùng được khi hết hạn." }
    }

    private func listen(marker: UUID) async {
        guard let ws = socket else { return }
        while !Task.isCancelled && marker == sessionMarker {
            do {
                let frame = try await ws.receive()
                guard marker == sessionMarker else { return }
                switch frame {
                case .string(let text): try await handleText(text)
                case .data(let packet): try handleData(packet)
                @unknown default: break
                }
            } catch {
                guard marker == sessionMarker else { return }
                stop(clearStatus: false)
                message = "Kết nối Online đã ngắt: \(error.localizedDescription). Tạo link mới để kết nối lại."
                return
            }
        }
    }

    private func handleText(_ text: String) async throws {
        guard let bytes = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "ready":
            connecting = false
            connected = true
            message = "Đã kết nối máy chủ. Mở link trên Chrome/Edge của PC."
        case "peer":
            peerOnline = json["online"] as? Bool ?? false
            message = peerOnline ? "PC đã ghép nối. Sẵn sàng truyền file mã hóa." : "Đang đợi PC mở link để ghép nối."
        case "enc":
            guard let encoded = json["blob"] as? String,
                  let sealed = Data(base64Encoded: encoded),
                  let plain = try? open(sealed),
                  let detail = try JSONSerialization.jsonObject(with: plain) as? [String: Any],
                  let event = detail["type"] as? String else { return }
            try await handleControl(event, detail)
        default: break
        }
    }

    private func handleControl(_ type: String, _ json: [String: Any]) async throws {
        switch type {
        case "file-start":
            guard incomingFile == nil,
                  let id = json["id"] as? String,
                  let name = json["name"] as? String,
                  let length = json["size"] as? NSNumber else { return }
            let size = length.int64Value
            guard (0...Int64(Self.maximumFileSize)).contains(size) else {
                message = "PC gửi file vượt giới hạn 50 MB."
                return
            }
            let safeName = Self.cleanName(name)
            let location = SendModel.receivedDir.appendingPathComponent(
                UUID().uuidString + "__" + safeName + ".part")
            guard FileManager.default.createFile(atPath: location.path, contents: nil) else {
                message = "Không tạo được file nhận."
                return
            }
            do {
                incomingFile = try FileHandle(forWritingTo: location)
                incomingTemporary = location
                incomingID = id
                incomingName = safeName
                incomingExpected = size
                incomingReceived = 0
                progress = 0
                progressTitle = "PC → iPhone: " + safeName
            } catch {
                try? FileManager.default.removeItem(at: location)
                message = "Lỗi bộ nhớ iPhone: \(error.localizedDescription)"
            }
        case "file-end":
            guard incomingFile != nil,
                  let id = json["id"] as? String,
                  id == incomingID,
                  incomingExpected == incomingReceived else {
                cleanupIncoming()
                message = "File chưa đủ dữ liệu hoặc sai mã phiên; đã hủy."
                return
            }
            guard let temporary = incomingTemporary else { return }
            try incomingFile?.close()
            incomingFile = nil
            let final = temporary.deletingPathExtension()
            do {
                try FileManager.default.moveItem(at: temporary, to: final)
                let name = incomingName
                cleanupIncoming()
                progress = 1
                progressTitle = "Đã nhận: " + name
                message = "Đã lưu file từ PC: " + name
                didReceive?()
                try await sendControl(["type": "file-ack", "id": id])
            } catch {
                cleanupIncoming()
                message = "Không thể hoàn thành file nhận: \(error.localizedDescription)"
            }
        case "file-ack":
            guard let id = json["id"] as? String else { return }
            acknowledgedReceipt = id
            if awaitingReceipt == id {
                message = "PC đã nhận file và chuẩn bị cho phép tải xuống."
            }
        case "file-cancel":
            cleanupIncoming()
            message = "PC đã hủy gửi file."
        default: break
        }
    }

    private func handleData(_ bytes: Data) throws {
        guard let writer = incomingFile else { return }
        let plain = try open(bytes)
        guard incomingReceived + Int64(plain.count) <= incomingExpected,
              incomingReceived + Int64(plain.count) <= Int64(Self.maximumFileSize) else {
            cleanupIncoming()
            message = "File không khớp dung lượng khai báo."
            return
        }
        try writer.write(contentsOf: plain)
        incomingReceived += Int64(plain.count)
        progress = incomingExpected == 0 ? 1 : Double(incomingReceived) / Double(incomingExpected)
    }

    func send(files: [SharedTransferFile]) {
        guard maySend, !files.isEmpty else {
            message = "Hãy chọn file và đợi PC kết nối."
            return
        }
        busy = true
        let marker = sessionMarker
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for file in files {
                    try Task.checkCancellation()
                    guard marker == self.sessionMarker else { return }
                    guard file.size <= Int64(Self.maximumFileSize) else {
                        throw NSError(domain: "BSend", code: 4, userInfo: [
                            NSLocalizedDescriptionKey: "File \(file.name) vượt 50 MB (giới hạn bản thử nghiệm)."
                        ])
                    }
                    let id = UUID().uuidString.lowercased()
                    self.progressTitle = "iPhone → PC: " + file.name
                    self.progress = 0
                    self.awaitingReceipt = id
                    self.acknowledgedReceipt = nil
                    try await self.sendControl([
                        "type": "file-start", "id": id,
                        "name": file.name, "size": file.size
                    ])
                    let handle = try FileHandle(forReadingFrom: file.url)
                    defer { try? handle.close() }
                    var sent: Int64 = 0
                    while true {
                        try Task.checkCancellation()
                        guard marker == self.sessionMarker, self.peerOnline else {
                            throw NSError(domain: "BSend", code: 5, userInfo: [
                                NSLocalizedDescriptionKey: "Đã mất kết nối PC."
                            ])
                        }
                        guard let chunk = try handle.read(upToCount: 48 * 1024), !chunk.isEmpty else { break }
                        try await self.sendBinary(chunk)
                        sent += Int64(chunk.count)
                        self.progress = file.size == 0 ? 1 : Double(sent) / Double(file.size)
                        await Task.yield()
                    }
                    try await self.sendControl(["type": "file-end", "id": id])
                    self.message = "Đã gửi đủ dữ liệu; chờ PC xác nhận nhận file..."
                    // An acknowledgment means PC assembled the blob; it does not prove a user saved it to disk.
                    for _ in 0..<240 {
                        if self.acknowledgedReceipt == id { break }
                        try Task.checkCancellation()
                        try await Task.sleep(for: .milliseconds(500))
                    }
                    guard self.acknowledgedReceipt == id else {
                        throw NSError(domain: "BSend", code: 6, userInfo: [
                            NSLocalizedDescriptionKey: "PC chưa xác nhận nhận đủ file trong 120 giây."
                        ])
                    }
                    self.message = "PC đã nhận file \(file.name), có thể bấm tải xuống."
                    self.awaitingReceipt = nil
                }
            } catch {
                if marker == self.sessionMarker {
                    try? await self.sendControl(["type": "file-cancel"])
                    self.message = "Lỗi gửi Online: \(error.localizedDescription)"
                }
            }
            if marker == self.sessionMarker {
                self.busy = false
                self.uploadTask = nil
            }
        }
    }

    private func sendControl(_ body: [String: Any]) async throws {
        let clear = try JSONSerialization.data(withJSONObject: body)
        let sealed = try seal(clear)
        let wire = try JSONSerialization.data(withJSONObject: [
            "type": "enc", "blob": sealed.base64EncodedString()
        ])
        guard let socket, let text = String(data: wire, encoding: .utf8) else {
            throw NSError(domain: "BSend", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "WebSocket không còn khả dụng."
            ])
        }
        try await socket.send(.string(text))
    }
    private func sendBinary(_ bytes: Data) async throws {
        guard let socket else {
            throw NSError(domain: "BSend", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "Phiên Online đã kết thúc."
            ])
        }
        try await socket.send(.data(try seal(bytes)))
    }
    private func seal(_ clear: Data) throws -> Data {
        guard let sharedKey else {
            throw NSError(domain: "BSend", code: 9, userInfo: [
                NSLocalizedDescriptionKey: "Không tìm thấy khóa mã hóa."
            ])
        }
        let sealed = try AES.GCM.seal(clear, using: sharedKey)
        guard let packet = sealed.combined else {
            throw NSError(domain: "BSend", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Không thể mã hóa dữ liệu."
            ])
        }
        return packet
    }
    private func open(_ packet: Data) throws -> Data {
        guard let sharedKey else {
            throw NSError(domain: "BSend", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Phiên mã hóa không hợp lệ."
            ])
        }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: packet), using: sharedKey)
    }

    private func cleanupIncoming() {
        try? incomingFile?.close()
        incomingFile = nil
        if let temporary = incomingTemporary {
            try? FileManager.default.removeItem(at: temporary)
        }
        incomingTemporary = nil
        incomingID = nil
        incomingName = ""
        incomingExpected = 0
        incomingReceived = 0
    }

    private static func cleanName(_ input: String) -> String {
        let filtered = String(input.unicodeScalars.filter {
            $0.value >= 32 && $0.value != 127
        })
        let safe = filtered.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((safe.isEmpty ? "received-file" : safe).prefix(140))
    }
}
