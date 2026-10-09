import Foundation
import CryptoKit
import UIKit

struct BSendOnlineSession: Decodable {
    let room: String
    let expiresAt: Int64
    let ownerWebSocketURL: String
    let guestURL: String
    let code: String
    let shortURL: String
}

@MainActor
final class BSendOnlineModel: ObservableObject {
    // No fixed app-level file size cap: files are transferred in small chunks.
    // Practical limit: free storage, session expiry, and network reliability.
    static let chunkSize = 48 * 1024
    static let progressWindow = 16
    static let relay = "https://bachsend-relay.mrbach222.workers.dev"

    @Published private(set) var shareURL: String?
    @Published private(set) var shortCode: String?
    @Published private(set) var shortURL: String?
    @Published private(set) var pendingVerification = false
    @Published private(set) var pairingApproved = false
    @Published private(set) var verificationCode: String?
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
    private var roomID = ""
    private var incomingFile: FileHandle?
    private var incomingTemporary: URL?
    private var incomingID: String?
    private var incomingName = ""
    private var incomingExpected: Int64 = 0
    private var incomingReceived: Int64 = 0
    private var incomingChunks = 0
    private var pendingProgressId: String?
    private var progressAcknowledged: Int64 = 0
    private var awaitingReceipt: String?
    private var acknowledgedReceipt: String?
    var didReceive: (() -> Void)?

    var isActive: Bool { connected || connecting }
    var maySend: Bool { connected && peerOnline && pairingApproved && !busy }
    var canClose: Bool { connected || connecting || shortCode != nil }

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
                self.shortCode = session.code
                self.shortURL = session.shortURL
                self.roomID = session.room
                self.pairingApproved = false
                self.pendingVerification = false
                self.verificationCode = nil
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

    // iOS may suspend a normal WebSocket in the background. Do not deliberately
    // close a healthy socket when Home is pressed. Preserve E2E pairing keys.
    // A finite background task is used only for transfers that are in progress.
    private var isInBackground = false
    private var backgroundTransferTask: UIBackgroundTaskIdentifier = .invalid
    private var reconnectTask: Task<Void, Never>?
    private var reconnectTries = 0

    func pauseForBackground() {
        isInBackground = true
        if busy && backgroundTransferTask == .invalid {
            backgroundTransferTask = UIApplication.shared.beginBackgroundTask(
                withName: "B Send - Finishing transfer") { [weak self] in
                Task { @MainActor [weak self] in self?.endTransferTime() }
            }
        }
        if isActive {
            message = "Phiên ghép nối vẫn được giữ. iOS có thể tạm ngưng đường truyền khi về màn hình chính."
        }
    }

    func resumeAfterBackground() {
        isInBackground = false
        endTransferTime()
        guard ownerURL != nil, shareURL != nil else { return }
        if let expiry, Date() >= expiry {
            stop(clearStatus: false)
            message = "Phiên đã hết hạn. Hãy tạo mã mới."
            return
        }
        if connected, let socket {
            socket.sendPing { [weak self] error in
                guard error != nil else { return }
                Task { @MainActor [weak self] in self?.scheduleReconnect() }
            }
        } else {
            scheduleReconnect()
        }
    }

    private func endTransferTime() {
        if backgroundTransferTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTransferTask)
            backgroundTransferTask = .invalid
        }
    }

    private func scheduleReconnect() {
        guard ownerURL != nil, !isInBackground else { return }
        reconnectTask?.cancel()
        reconnectTries += 1
        let delay = min(Double(reconnectTries) * 1.5, 8.0)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.reconnectNow()
        }
    }

    private func reconnectNow() {
        guard let ownerURL, !isInBackground else { return }
        if let expiry, Date() >= expiry {
            stop(clearStatus: false)
            message = "Phiên đã hết hạn. Tạo mã mới để ghép nối."
            return
        }
        sessionMarker = UUID()
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectTries = 0
        endTransferTime()
        uploadTask?.cancel()
        uploadTask = nil
        receivingTask?.cancel()
        receivingTask = nil
        pingTask?.cancel()
        pingTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        cleanupIncoming()
        busy = false
        connecting = true
        connected = false
        peerOnline = false
        progress = 0
        progressTitle = ""
        awaitingReceipt = nil
        acknowledgedReceipt = nil
        // sharedKey and pairingApproved are intentionally retained.
        message = "Đang nối lại phiên, không cần nhập lại mã ghép nối..."
        connectSocket(ownerURL, marker: sessionMarker)
    }

    private func connectSocket(_ owner: URL, marker: UUID) {
        guard marker == sessionMarker else { return }
        let ws = URLSession.shared.webSocketTask(with: owner)
        socket = ws
        ws.resume()
        receivingTask = Task { [weak self] in
            await self?.listen(marker: marker)
        }
        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && marker == self.sessionMarker {
                try? await Task.sleep(for: .seconds(18))
                guard !Task.isCancelled, marker == self.sessionMarker else { break }
                ws.sendPing { [weak self] error in
                    guard error != nil else { return }
                    Task { @MainActor [weak self] in self?.scheduleReconnect() }
                }
            }
        }
    }

    private func stop(clearStatus: Bool) {
        sessionMarker = UUID()
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectTries = 0
        endTransferTime()
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
        roomID = ""
        shortCode = nil
        shortURL = nil
        pairingApproved = false
        pendingVerification = false
        verificationCode = nil
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
                case .data(let packet): try await handleData(packet)
                @unknown default: break
                }
            } catch {
                guard marker == sessionMarker else { return }
                connected = false
                connecting = false
                peerOnline = false
                if !isInBackground {
                    message = "Kết nối bị gián đoạn: \(error.localizedDescription). Đang thử nối lại..."
                    scheduleReconnect()
                } else {
                    message = "Kết nối bị tạm ngưng khi iPhone vào nền. Mở lại app để tự nối."
                }
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
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectTries = 0
            connecting = false
            connected = true
            message = "Đã kết nối máy chủ. Mở link trên Chrome/Edge của PC."
        case "peer":
            peerOnline = json["online"] as? Bool ?? false
            if !peerOnline {
                // Keep the authenticated key for the SAME browser reconnecting.
                pendingVerification = false
                verificationCode = nil
                message = "PC tạm mất kết nối, đang chờ PC quay lại."
            } else if pairingApproved && sharedKey != nil {
                message = "PC đã quay lại. Đang khôi phục phiên đã xác minh..."
            } else {
                message = "PC đã vào phòng. Đang xác thực mã bảo mật..."
            }
        case "key-offer":
            guard let encoded = json["pub"] as? String,
                  let data = Data(base64Encoded: encoded),
                  data.count == 65 else { return }
            let remote = try P256.KeyAgreement.PublicKey(x963Representation: data)
            let privateKey = P256.KeyAgreement.PrivateKey()
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: remote)
            let info = Data(("B Send v0.5:" + roomID).utf8)
            let derived = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                          salt: Data(),
                                                          sharedInfo: info,
                                                          outputByteCount: 32)
            sharedKey = derived
            pairingApproved = false
            pendingVerification = true
            verificationCode = nil
            guard let socket else { return }
            let answer = [
                "type": "key-answer",
                "pub": privateKey.publicKey.x963Representation.base64EncodedString()
            ]
            let answerData = try JSONSerialization.data(withJSONObject: answer)
            guard let text = String(data: answerData, encoding: .utf8) else { return }
            try await socket.send(.string(text))
            message = "Máy tính đang yêu cầu kết nối. Bấm Chấp nhận để cho phép gửi và nhận file."
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
        case "resume-probe":
            guard pairingApproved, sharedKey != nil,
                  let check = json["nonce"] as? String,
                  check.count >= 12, check.count <= 80 else { return }
            try await sendControl(["type": "resume-ack", "nonce": check])
            message = "Đã khôi phục phiên ghép nối an toàn với PC."
        case "file-start":
            guard incomingFile == nil,
                  let id = json["id"] as? String,
                  let name = json["name"] as? String,
                  let length = json["size"] as? NSNumber else { return }
            let size = length.int64Value
            guard size >= 0 else { return }
            // Preflight free disk space before accepting a file. This is not a
            // configured transfer limit; it protects the user's device.
            let disk = (try? FileManager.default.attributesOfFileSystem(
                forPath: SendModel.receivedDir.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            guard disk > 0 && disk >= size + 8 * 1024 * 1024 else {
                message = "iPhone không đủ dung lượng trống để nhận file."
                try? await sendControl(["type": "file-cancel", "id": id, "reason": "disk-full"])
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
                incomingChunks = 0
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
        case "file-progress":
            guard let id = json["id"] as? String,
                  let received = json["received"] as? NSNumber,
                  id == pendingProgressId else { return }
            progressAcknowledged = max(progressAcknowledged, received.int64Value)
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

    private func handleData(_ bytes: Data) async throws {
        guard let writer = incomingFile else { return }
        let plain = try open(bytes)
        guard incomingReceived + Int64(plain.count) <= incomingExpected else {
            cleanupIncoming()
            message = "File không khớp dung lượng khai báo."
            return
        }
        try writer.write(contentsOf: plain)
        incomingReceived += Int64(plain.count)
        incomingChunks += 1
        progress = incomingExpected == 0 ? 1 : Double(incomingReceived) / Double(incomingExpected)
        if incomingChunks % Self.progressWindow == 0, let id = incomingID {
            try await sendControl(["type": "file-progress", "id": id, "received": incomingReceived])
        }
    }

    func approvePairing() {
        guard pendingVerification, sharedKey != nil else { return }
        Task {
            do {
                try await sendControl(["type": "pair-approved"])
                pairingApproved = true
                pendingVerification = false
                verificationCode = nil
                message = "Đã chấp nhận máy tính. Có thể gửi và nhận file Online."
            } catch {
                message = "Lỗi xác nhận ghép nối: \(error.localizedDescription)"
            }
        }
    }

    func rejectPairing() {
        stop(clearStatus: false)
        message = "Đã từ chối ghép nối. Tạo link mới để thử lại."
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
                    guard file.size >= 0 else { throw NSError(domain: "BSend", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: "Không xác định được dung lượng file."
                    ]) }
                    let id = UUID().uuidString.lowercased()
                    self.progressTitle = "iPhone → PC: " + file.name
                    self.progress = 0
                    self.awaitingReceipt = id
                    self.acknowledgedReceipt = nil
                    self.pendingProgressId = id
                    self.progressAcknowledged = 0
                    try await self.sendControl([
                        "type": "file-start", "id": id,
                        "name": file.name, "size": file.size
                    ])
                    let handle = try FileHandle(forReadingFrom: file.url)
                    defer { try? handle.close() }
                    var sent: Int64 = 0
                    var chunksSent = 0
                    while true {
                        try Task.checkCancellation()
                        guard marker == self.sessionMarker, self.peerOnline else {
                            throw NSError(domain: "BSend", code: 5, userInfo: [
                                NSLocalizedDescriptionKey: "Đã mất kết nối PC."
                            ])
                        }
                        guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }
                        try await self.sendBinary(chunk)
                        sent += Int64(chunk.count)
                        chunksSent += 1
                        self.progress = file.size == 0 ? 1 : Double(sent) / Double(file.size)
                        // Keep in-flight data bounded to ~768 KiB, even for multi-GB files.
                        if chunksSent % Self.progressWindow == 0 {
                            var attempts = 0
                            while self.progressAcknowledged < sent {
                                try Task.checkCancellation()
                                guard self.peerOnline, marker == self.sessionMarker else {
                                    throw NSError(domain: "BSend", code: 5, userInfo: [
                                        NSLocalizedDescriptionKey: "Mất kết nối khi chuyển file."
                                    ])
                                }
                                try await Task.sleep(for: .milliseconds(100))
                                attempts += 1
                                if attempts > 900 { throw NSError(domain: "BSend", code: 13, userInfo: [
                                    NSLocalizedDescriptionKey: "PC không xác nhận tiến độ trong 90 giây."
                                ]) }
                            }
                        }
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
                    self.message = "PC đã nhận file \(file.name)."
                    self.awaitingReceipt = nil
                    self.pendingProgressId = nil
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
                self.endTransferTime()
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
        incomingChunks = 0
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
