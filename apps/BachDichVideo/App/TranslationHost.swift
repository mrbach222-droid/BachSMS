import Foundation

final class TranslationHost {
    private let queue = DispatchQueue(label: "vn.bach.dich.host")
    private var server: LocalHTTPServer?
    private var gate: PairingGate?
    private var translator: GeminiTranslator?
    private var timer: DispatchSourceTimer?
    private var policy = TranslationPolicy(interval: 3, limit: 120)
    private var settings = AppSettings()
    private var key = ""
    private var state = CaptureSnapshot()
    private var command = BridgeCommand()
    private var lastCandidate = Date.distantPast
    private var lastHeartbeat = Date.distantPast
    private var currentCandidate = ""
    private var cachedTranslation = ""
    private var blockedMessage = ""
    private var startedAt = Date()
    var onSnapshot: ((CaptureSnapshot) -> Void)?

    func prepare(settings: AppSettings, key: String, foreground: Bool,
                 completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            self.shutdownInternal()
            self.settings = settings; self.key = key
            self.state = CaptureSnapshot(); self.state.message = "Chờ ghép nối phần thu màn hình."
            self.command = BridgeCommand(paused: false, stop: false, appVisible: foreground)
            self.policy = TranslationPolicy(interval: settings.minimumInterval, limit: settings.sessionLimit)
            self.cachedTranslation = ""; self.blockedMessage = ""; self.startedAt = Date()
            self.lastCandidate = .distantPast; self.lastHeartbeat = .distantPast
            let code = String(format: "%06d", Int.random(in: 0...999999))
            let token = UUID().uuidString + UUID().uuidString
            self.gate = PairingGate(code: code, token: token, now: ProcessInfo.processInfo.systemUptime)
            self.translator = GeminiTranslator()
            let server = LocalHTTPServer(queue: self.queue) { [weak self] request in
                self?.handle(request) ?? BridgeReply(ok: false, message: "Phiên đã dừng.")
            }
            self.server = server
            do {
                try server.start { [weak self] ready in
                    guard let self = self else { return }
                    if ready { self.emit(); DispatchQueue.main.async { completion(.success(code)) } }
                    else {
                        self.shutdownInternal()
                        DispatchQueue.main.async { completion(.failure(Self.error("Không mở được kết nối trong máy. Đóng phiên cũ và thử lại."))) }
                    }
                }
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
                timer.setEventHandler { [weak self] in self?.tick() }
                self.timer = timer; timer.resume()
            } catch {
                self.shutdownInternal()
                DispatchQueue.main.async { completion(.failure(Self.error("Không mở được kết nối nội bộ của app."))) }
            }
        }
    }
    func setForeground(_ visible: Bool) { queue.async { self.command.appVisible = visible } }
    func pause(_ paused: Bool) { queue.async { self.command.paused = paused; self.policy.discardPending() } }
    func stop() { queue.async { self.finish("Đã dừng phiên dịch."); self.shutdownInternal() } }
    private func handle(_ request: BridgeHTTPRequest) -> BridgeReply {
        let now = ProcessInfo.processInfo.systemUptime
        if request.path == "/pair" {
            struct Code: Decodable { let code: String }
            guard let code = try? JSONDecoder().decode(Code.self, from: request.body),
                  let token = gate?.pair(code: code.code, now: now) else {
                return BridgeReply(ok: false, message: "Mã sai, hết hạn hoặc đã dùng. Quay về app chính bấm Lưu để lấy mã mới.")
            }
            return BridgeReply(ok: true, message: "Đã ghép nối.", token: token, settings: settings, command: command)
        }
        guard gate?.accepts(request.token, now: now) == true else {
            return BridgeReply(ok: false, message: "Phiên ghép nối không hợp lệ hoặc đã kết thúc.", command: BridgeCommand(stop: true))
        }
        if request.path == "/finish" {
            finish("Phần thu màn hình đã kết thúc.")
            gate?.invalidate()
            translator?.cancel(); translator = nil; key = ""
            return BridgeReply(ok: true, command: BridgeCommand(stop: true))
        }
        guard let update = try? JSONDecoder().decode(BridgeUpdate.self, from: request.body) else {
            return BridgeReply(ok: false, message: "Không đọc được dữ liệu cục bộ.")
        }
        state.active = true; lastHeartbeat = Date()
        state.lastVideoAt = update.videoAt; state.lastAudioAt = update.audioAt
        if let status = update.speechStatus, !status.isEmpty { state.message = String(status.prefix(300)) }
        if let text = update.text, canTranslate { offer(text) }
        return BridgeReply(ok: true, command: command)
    }
    private var canTranslate: Bool {
        state.active && !command.stop && !command.paused && !command.appVisible && blockedMessage.isEmpty
    }
    private func offer(_ text: String) {
        let normalized = TranslationPolicy.normalized(text)
        guard normalized.count >= 2 else { policy.discardPending(); currentCandidate = ""; return }
        guard !normalized.localizedCaseInsensitiveContains("BÁCH DỊCH"),
              normalized != TranslationPolicy.normalized(state.translation) else { return }
        lastCandidate = Date(); currentCandidate = String(normalized.prefix(900))
        if currentCandidate == policy.lastSucceeded && !cachedTranslation.isEmpty {
            state.source = currentCandidate; state.translation = cachedTranslation; state.translatedAt = Date()
        }
        policy.offer(currentCandidate)
    }
    private func tick() {
        if Date().timeIntervalSince(startedAt) > 1800 {
            finish("Phiên thử đã đủ 30 phút. Bắt đầu phiên mới để tiếp tục.")
            gate?.invalidate(); translator?.cancel(); translator = nil; key = ""
        }
        if state.active && Date().timeIntervalSince(lastHeartbeat) > 12 {
            state.source = ""; state.translation = ""; state.translatedAt = nil
            state.message = "Mất kết nối với phần thu màn hình. Dừng phiên rồi bắt đầu lại."
            command.stop = true
        }
        state.paused = command.paused
        if !blockedMessage.isEmpty { state.message = blockedMessage }
        else if command.stop { }
        else if command.paused || command.appVisible {
            policy.discardPending(); state.source = ""; state.translation = ""; state.translatedAt = nil
            state.message = command.appVisible ? "Quay sang app xem video sau khi ghép nối." : "Đang tạm dừng dịch."
        } else if state.active {
            if Date().timeIntervalSince(lastCandidate) > 8 {
                policy.discardPending(); state.source = ""; state.translation = ""; state.translatedAt = nil
                state.message = settings.mode == .speech ? "Đang chờ nhận dạng tiếng video…" : "Đang tìm chữ/phụ đề trong vùng đã chọn…"
            }
            translateNext()
        }
        emit()
    }
    private func translateNext() {
        guard canTranslate else { return }
        if policy.reachedLimit { state.message = "Đã đủ \(settings.sessionLimit) yêu cầu của phiên."; return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let text = policy.take(now: now) else { return }
        state.requests = policy.requests; state.message = "Đang dịch…"
        let id = state.sessionID
        translator?.translate(text, model: settings.model, key: key) { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard self.state.sessionID == id, !self.command.stop else { return }
                let finished = ProcessInfo.processInfo.systemUptime
                switch result {
                case .success(let translated):
                    self.policy.complete(text: text, success: true, now: finished)
                    self.cachedTranslation = translated
                    if self.canTranslate && finished - now < 12 && Date().timeIntervalSince(self.lastCandidate) < 8 &&
                        (self.settings.mode == .speech || self.currentCandidate == text) {
                        self.state.source = text; self.state.translation = translated
                        self.state.translatedAt = Date(); self.state.translations += 1
                        self.state.latency = finished - now; self.state.message = "Đang dịch video"
                    }
                case .failure(let error):
                    self.policy.complete(text: text, success: false, now: finished, retryAfter: error.retryAfter)
                    self.state.message = error.message
                    if error.fatal { self.blockedMessage = error.message }
                }
                self.emit()
            }
        }
    }
    private func finish(_ message: String) {
        command.stop = true; command.paused = true
        state.active = false; state.source = ""; state.translation = ""; state.translatedAt = nil
        cachedTranslation = ""; state.message = message; emit()
    }
    private func emit() {
        state.updatedAt = Date()
        let copy = state
        DispatchQueue.main.async { [weak self] in self?.onSnapshot?(copy) }
    }
    private func shutdownInternal() {
        gate?.invalidate(); gate = nil
        timer?.cancel(); timer = nil
        translator?.cancel(); translator = nil; key = ""
        server?.stop(); server = nil
    }
    private static func error(_ message: String) -> Error {
        NSError(domain: "BachBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
