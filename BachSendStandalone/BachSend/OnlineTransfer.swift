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
    @Published private(set) var privateDeviceURL: String?
    @Published var deviceName: String = UserDefaults.standard.string(forKey: "bsend.deviceDisplayName") ?? "iPhone của tôi"
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
    @Published var turboMode = "Tự động"
    @Published private(set) var uploadMBps: Double = 0
    @Published private(set) var remainingSeconds: Double = 0
    @Published private(set) var sentBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published var message = "Nhấn Tạo link Online để ghép nối PC ở mạng khác."
    @Published private(set) var expiry: Date?

    private var socket: URLSessionWebSocketTask?
    private var ownerURL: URL?
    private var receivingTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var sessionMarker = UUID()
    private var sharedKey: SymmetricKey?
    private var pendingPCPublicKey: Data?
    private var trustedChallenge: String?
    private var roomID = ""
    private var incomingFile: FileHandle?
    private var incomingTemporary: URL?
    private var incomingID: String?
    private var incomingName = ""
    private var incomingExpected: Int64 = 0
    private var incomingReceived: Int64 = 0
    private var incomingChunks = 0
    private var incomingSHA256: String?
    private var readyOffset: Int64?
    private var readyID: String?
    private var readySHA: String?
    private var queuedOutgoing: [SharedTransferFile] = []
    private var outgoingTransferIDs: [UUID: String] = [:]
    private var pendingProgressId: String?
    private var progressAcknowledged: Int64 = 0
    private var remoteCancelledTransfer = false
    private var awaitingReceipt: String?
    private var acknowledgedReceipt: String?
    var didReceive: (() -> Void)?
    // Only after the PC confirms the full file: caller removes its B Send
    // staging copy (never the user's original in Photos/Files).
    var didUpload: ((UUID) -> Void)?

    var isActive: Bool { connected || connecting }
    var maySend: Bool { connected && peerOnline && pairingApproved && !busy }
    var canClose: Bool { connected || connecting || shortCode != nil }

    init() {
        // The link is stable across sessions. Never store its secret in UserDefaults.
        privateDeviceURL = try? BSendDeviceIdentity.loadOrCreate().privateLink
    }

    func start() {
        guard !isActive else { return }
        let identity: BSendDeviceIdentity
        let requestPayload: Data
        do {
            identity = try BSendDeviceIdentity.loadOrCreate()
            let cleanName = String(deviceName.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(cleanName, forKey: "bsend.deviceDisplayName")
            requestPayload = try JSONSerialization.data(withJSONObject: [
                "deviceId": identity.id,
                "deviceOwnerSecret": identity.ownerSecret,
                "deviceLinkSecret": identity.linkSecret,
                "deviceName": cleanName.isEmpty ? "iPhone" : cleanName
            ])
            privateDeviceURL = identity.privateLink
        } catch {
            message = "Không tạo được link riêng: \(error.localizedDescription)"
            return
        }
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
                request.httpBody = requestPayload
                request.timeoutInterval = 20
                let (body, response) = try await URLSession.shared.data(for: request)
                guard marker == self.sessionMarker else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                    throw NSError(domain: "BSend", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Máy chủ chưa tạo được phiên riêng cho iPhone. Cần cập nhật Cloudflare Worker v0.6."
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

    // Quick Background mode intentionally uses only Apple's finite background
    // execution window. It does not register audio, VoIP or location modes.
    // iOS decides the duration; 60 seconds is a testing goal, NOT a guarantee.
    private var isInBackground = false
    private var backgroundTransferTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundGraceExpired = false
    private var reconnectTask: Task<Void, Never>?
    private var reconnectTries = 0
    private var resumePingID: UUID?
    @Published private(set) var lastBackgroundSeconds: Int = 0
    @Published private(set) var backgroundHolding = false
    private var enteredBackgroundAt: Date?

    private var mayReconnectInCurrentState: Bool {
        !isInBackground || (!backgroundGraceExpired && backgroundTransferTask != .invalid)
    }

    func pauseForBackground() {
        guard !isInBackground else { return }
        isInBackground = true
        enteredBackgroundAt = Date()
        backgroundGraceExpired = false

        // v0.5.5 only requested a background task DURING transfers. That
        // meant a user replying to a message while idle would be suspended.
        // Start a finite task for ANY active paired/connecting session.
        if ownerURL != nil && backgroundTransferTask == .invalid {
            backgroundTransferTask = UIApplication.shared.beginBackgroundTask(
                withName: "B Send - Quick Background Online") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.backgroundGraceExpired = true
                    self.backgroundHolding = false
                    self.endTransferTime()
                    if self.isInBackground {
                        self.message = "iOS đã hết thời gian chạy nền. Phiên vẫn được giữ và tự nối lại khi mở B Send."
                    }
                }
            }
        }
        backgroundHolding = backgroundTransferTask != .invalid
        if ownerURL != nil {
            message = backgroundHolding
                ? "Đang giữ WebSocket trong thời gian chạy nền iOS cấp. PC có thể gửi khi kết nối còn hoạt động."
                : "iOS không cấp thêm thời gian nền. Giữ phiên và sẽ tự kết nối khi mở lại."
        }
    }

    func resumeAfterBackground() {
        isInBackground = false
        if let enteredBackgroundAt {
            lastBackgroundSeconds = max(0, Int(Date().timeIntervalSince(enteredBackgroundAt)))
            self.enteredBackgroundAt = nil
        }
        backgroundHolding = false
        backgroundGraceExpired = false
        endTransferTime()
        guard ownerURL != nil, shareURL != nil else { return }
        if let expiry, Date() >= expiry {
            stop(clearStatus: false)
            message = "Phiên đã hết hạn. Hãy tạo mã mới."
            return
        }
        if connected, let socket {
            // A stale URLSessionWebSocketTask can silently stop responding
            // after iOS suspends the app. Verify with a bounded ping, then
            // reconnect in the SAME encrypted session if necessary.
            let checkID = UUID()
            resumePingID = checkID
            socket.sendPing { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.resumePingID == checkID else { return }
                    self.resumePingID = nil
                    if error != nil {
                        self.message = "WebSocket bị ngắt sau khi quay lại. Đang nối lại phiên cũ..."
                        self.scheduleReconnect()
                    } else {
                        self.message = "WebSocket vẫn phản hồi sau \(self.lastBackgroundSeconds) giây chuyển ứng dụng."
                    }
                }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard let self, self.resumePingID == checkID else { return }
                self.resumePingID = nil
                if !self.busy { self.scheduleReconnect() }
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
        backgroundHolding = false
    }

    private func scheduleReconnect() {
        guard ownerURL != nil, mayReconnectInCurrentState else { return }
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
        guard let ownerURL, mayReconnectInCurrentState else { return }
        if let expiry, Date() >= expiry {
            stop(clearStatus: false)
            message = "Phiên đã hết hạn. Tạo mã mới để ghép nối."
            return
        }
        sessionMarker = UUID()
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectTries = 0
        resumePingID = nil
        // Do not end the finite iOS background task during a reconnect.
        // Keep the grace window available for the replacement WebSocket.
        if !isInBackground { endTransferTime() }
        uploadTask?.cancel()
        uploadTask = nil
        receivingTask?.cancel()
        receivingTask = nil
        pingTask?.cancel()
        pingTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        // Keep the partial .part file in this encrypted room for Smart Resume.
        // It is discarded only when the session is explicitly stopped/expired.
        busy = false
        connecting = true
        connected = false
        peerOnline = false
        progress = 0
        progressTitle = ""
        uploadMBps = 0
        remainingSeconds = 0
        sentBytes = 0
        totalBytes = 0
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
        isInBackground = false
        enteredBackgroundAt = nil
        backgroundGraceExpired = false
        backgroundHolding = false
        resumePingID = nil
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
        queuedOutgoing.removeAll()
        outgoingTransferIDs.removeAll()
        readyID = nil
        readyOffset = nil
        readySHA = nil
        sharedKey = nil
        pendingPCPublicKey = nil
        trustedChallenge = nil
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
                if mayReconnectInCurrentState {
                    message = isInBackground
                        ? "Đang khôi phục WebSocket trong thời gian nền được cấp..."
                        : "Kết nối bị gián đoạn: \(error.localizedDescription). Đang thử nối lại..."
                    scheduleReconnect()
                } else {
                    message = "iOS đã tạm ngưng kết nối. Mở lại B Send để nối tự động."
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
            pendingPCPublicKey = data
            trustedChallenge = nil
            pairingApproved = false
            let isPersonalPC = (try? BSendTrustedPCStore.contains(data)) ?? false
            pendingVerification = !isPersonalPC
            verificationCode = nil
            guard let socket else { return }
            let answer = [
                "type": "key-answer",
                "pub": privateKey.publicKey.x963Representation.base64EncodedString()
            ]
            let answerData = try JSONSerialization.data(withJSONObject: answer)
            guard let text = String(data: answerData, encoding: .utf8) else { return }
            try await socket.send(.string(text))
            if isPersonalPC {
                // Require an AES-GCM response to a fresh random challenge.
                // Replaying a trusted public key is NOT enough for auto approval.
                let challenge = UUID().uuidString.lowercased()
                trustedChallenge = challenge
                try await sendControl(["type": "trust-probe", "nonce": challenge])
                message = "Đang tự xác minh máy tính cá nhân đã tin cậy..."
            } else {
                message = "PC mới muốn kết nối. Bấm Chấp nhận một lần để ghi nhớ máy tính này."
            }
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
        case "trust-proof":
            guard let proof = json["nonce"] as? String,
                  let challenge = trustedChallenge, proof == challenge,
                  let publicKey = pendingPCPublicKey,
                  (try? BSendTrustedPCStore.contains(publicKey)) == true,
                  !pairingApproved else { return }
            trustedChallenge = nil
            // Only a browser possessing the paired private ECDH key can
            // decrypt trust-probe and encrypt trust-proof with this room key.
            try await sendControl(["type": "pair-approved"])
            pairingApproved = true
            pendingVerification = false
            message = "PC cá nhân đã tự kết nối an toàn. Không cần xác nhận lại."
            autoResumeOutgoingIfPossible()
        case "resume-probe":
            guard pairingApproved, sharedKey != nil,
                  let check = json["nonce"] as? String,
                  check.count >= 12, check.count <= 80 else { return }
            try await sendControl(["type": "resume-ack", "nonce": check])
            message = "Đã khôi phục phiên ghép nối an toàn với PC."
            autoResumeOutgoingIfPossible()
        case "file-start":
            guard incomingFile == nil,
                  let id = json["id"] as? String,
                  let name = json["name"] as? String,
                  let length = json["size"] as? NSNumber else { return }
            let size = length.int64Value
            guard size >= 0 else { return }
            let digest = (json["sha256"] as? String)?.lowercased()
            if let digest, !Self.validDigest(digest) {
                try? await sendControl(["type":"file-cancel","id":id,"reason":"bad-sha256"])
                return
            }
            // Resume only if this is precisely the SAME id, name, size and
            // declared digest within the SAME encrypted transfer room.
            if incomingFile != nil {
                if id == incomingID, size == incomingExpected,
                   Self.cleanName(name) == incomingName,
                   digest == incomingSHA256 {
                    try await sendControl([
                        "type":"file-ready","id":id,"offset":incomingReceived
                    ])
                } else {
                    try? await sendControl(["type":"file-cancel","id":id,"reason":"receiver-busy"])
                }
                return
            }
            // Preflight free disk space before accepting a file. This is not a
            // configured transfer limit; it protects the user's device.
            let disk = (try? FileManager.default.attributesOfFileSystem(
                forPath: SendModel.receivedDir.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            guard disk > 8 * 1024 * 1024 && size <= disk - 8 * 1024 * 1024 else {
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
                incomingSHA256 = digest
                progress = 0
                progressTitle = "PC → iPhone: " + safeName
                try await sendControl(["type":"file-ready","id":id,"offset":0])
            } catch {
                try? FileManager.default.removeItem(at: location)
                message = "Lỗi bộ nhớ iPhone: \(error.localizedDescription)"
            }
        case "file-end":
            guard let id = json["id"] as? String,
                  id == incomingID, incomingFile != nil else { return }
            guard incomingExpected == incomingReceived,
                  let temporary = incomingTemporary else {
                message = "File chưa nhận đủ. Có thể truyền tiếp khi kết nối lại."
                try? await sendControl(["type":"file-cancel","id":id,"reason":"incomplete"])
                return
            }
            // Sender's SHA is inside the encrypted control envelope. Verify
            // every received byte before exposing the file or sending ACK.
            let finalDigest = (json["sha256"] as? String)?.lowercased()
            if let expected = incomingSHA256 {
                guard finalDigest == expected else {
                    cleanupIncoming()
                    try? await sendControl(["type":"file-cancel","id":id,"reason":"hash-metadata"])
                    message = "SHA-256 không khớp; file đã bị hủy."
                    return
                }
                try incomingFile?.close()
                incomingFile = nil
                let computed = try Self.fileSHA256(temporary)
                guard computed == expected else {
                    cleanupIncoming()
                    try? await sendControl(["type":"file-cancel","id":id,"reason":"sha256-mismatch"])
                    message = "SHA-256 kiểm tra thất bại. Đã xóa file sai."
                    return
                }
            } else {
                try incomingFile?.close()
                incomingFile = nil
            }
            let final = temporary.deletingPathExtension()
            do {
                try FileManager.default.moveItem(at: temporary, to: final)
                let name = incomingName
                cleanupIncoming()
                progress = 1
                progressTitle = "Đã nhận: " + name
                message = incomingSHA256 == nil
                    ? "Đã nhận file từ PC cũ (chưa kiểm tra SHA-256): " + name
                    : "✓ SHA-256 trùng khớp. Đã nhận: " + name
                let checked = incomingSHA256 != nil
                didReceive?()
                try await sendControl(["type": "file-ack", "id": id, "verified": checked])
            } catch {
                cleanupIncoming()
                message = "Không thể hoàn thành file nhận: \(error.localizedDescription)"
            }
        case "file-ready":
            guard let id = json["id"] as? String,
                  let offset = json["offset"] as? NSNumber,
                  offset.int64Value >= 0 else { return }
            readyID = id
            readyOffset = offset.int64Value
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
            if awaitingReceipt != nil { remoteCancelledTransfer = true }
            cleanupIncoming()
            message = "Đầu bên kia đã hủy hoặc không đủ dung lượng nhận file."
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
                trustedChallenge = nil
                verificationCode = nil
                if let publicKey = pendingPCPublicKey {
                    do {
                        try BSendTrustedPCStore.add(publicKey)
                        message = "Đã tin cậy PC cá nhân này. Lần sau chỉ cần mở web là tự kết nối."
                    } catch {
                        message = "PC đã kết nối, nhưng không lưu được tin cậy vào Keychain. Lần sau cần xác nhận lại."
                    }
                } else {
                    message = "Đã chấp nhận PC. Có thể truyền file Online."
                }
            } catch {
                message = "Lỗi xác nhận ghép nối: \(error.localizedDescription)"
            }
        }
    }

    func forgetTrustedComputers() {
        do {
            try BSendTrustedPCStore.clear()
            stop(clearStatus: false)
            message = "Đã quên PC tin cậy. Lần kết nối tiếp theo cần xác nhận lại."
        } catch {
            message = "Không thể xóa danh sách PC tin cậy: \(error.localizedDescription)"
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
                    self.uploadMBps = 0
                    self.remainingSeconds = 0
                    self.sentBytes = 0
                    self.totalBytes = file.size
                    let uploadStart = Date()
                    var lastStatsUpdate = Date.distantPast
                    var targetWindow = self.turboMode == "Turbo" ? 96 :
                        (self.turboMode == "Ổn định" ? 16 : 32)
                    self.awaitingReceipt = id
                    self.acknowledgedReceipt = nil
                    self.pendingProgressId = id
                    self.progressAcknowledged = 0
                    self.remoteCancelledTransfer = false
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
                        if self.remoteCancelledTransfer {
                            throw NSError(domain: "BSend", code: 14, userInfo: [
                                NSLocalizedDescriptionKey: "PC không nhận được file. Chọn thư mục lưu trên PC nếu gửi file lớn."
                            ])
                        }
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
                        if Date().timeIntervalSince(lastStatsUpdate) > 0.25 || sent == file.size {
                            let elapsed = max(0.01, Date().timeIntervalSince(uploadStart))
                            self.sentBytes = sent
                            self.uploadMBps = Double(sent) / elapsed / 1_048_576
                            self.remainingSeconds = self.uploadMBps > 0 ?
                                Double(max(0, file.size - sent)) / (self.uploadMBps * 1_048_576) : 0
                            lastStatsUpdate = Date()
                        }
                        // 16..128 encrypted frames are in flight, with adaptive
                        // ACK-controlled pacing. Each receiver ACKs every 16 frames.
                        if chunksSent % targetWindow == 0 {
                            let roundTripStart = Date()
                            var attempts = 0
                            while self.progressAcknowledged < sent {
                                try Task.checkCancellation()
                                guard self.peerOnline, marker == self.sessionMarker, !self.remoteCancelledTransfer else {
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
                            if self.turboMode == "Tự động" {
                                let ackSeconds = Date().timeIntervalSince(roundTripStart)
                                if ackSeconds < 0.6 { targetWindow = min(128, targetWindow * 2) }
                                else if ackSeconds > 2.5 { targetWindow = max(16, targetWindow / 2) }
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
                    self.message = "PC đã nhận file \(file.name). Đã xóa bản sao gửi tạm khỏi B Send."
                    try? handle.close()
                    self.didUpload?(file.id)
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
                if !self.isInBackground { self.endTransferTime() }
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
        incomingSHA256 = nil
    }

    private static func validDigest(_ digest: String) -> Bool {
        digest.count == 64 && digest.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    private static func fileSHA256(_ url: URL) throws -> String {
        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        var hash = SHA256()
        while let chunk = try reader.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
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
