import ReplayKit
import Foundation

final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "vn.bach.dich.capture", qos: .userInitiated)
    private let admissionLock = NSLock()
    private var videoInFlight = false
    private var lastAdmission: TimeInterval = 0
    private var state = CaptureSnapshot()
    private var settings = AppSettings()
    private var policy = TranslationPolicy(interval: 3, limit: 120)
    private var ocr: ScreenOCR?
    private var speech: DeviceSpeech?
    private var translator: GeminiTranslator?
    private var timer: DispatchSourceTimer?
    private var key = ""
    private var running = false
    private var blocked = false
    private var systemPaused = false
    private var previousPaused = false
    private var lastCandidate = Date.distantPast
    private var currentCandidate = ""
    private var blockingMessage = ""
    private var cachedTranslation = ""
    private var sessionStarted = Date()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.async {
            self.settings = SharedStore.settings
            self.state = CaptureSnapshot()
            self.state.active = true
            self.state.message = "Đã bật chia sẻ màn hình. Quay sang video cần dịch."
            self.running = true; self.blocked = false; self.blockingMessage = ""; self.sessionStarted = Date()
            guard self.settings.cloudConsent else {
                self.end("Cần đồng ý gửi chữ đã nhận diện đến Gemini trong app trước khi bắt đầu."); return
            }
            do {
                self.key = try APIKeyStore.load()
                guard !self.key.isEmpty else { self.end("Chưa lưu Gemini API key trong app."); return }
                self.policy = TranslationPolicy(interval: self.settings.minimumInterval, limit: self.settings.sessionLimit)
                self.translator = GeminiTranslator()
                self.ocr = ScreenOCR()
                if self.settings.mode == .speech {
                    self.speech = DeviceSpeech(locale: self.settings.speechLocale, queue: self.queue,
                        output: { [weak self] text in self?.offer(text) },
                        status: { [weak self] message in self?.state.message = message })
                }
                try SharedStore.write(self.state, to: "snapshot.json")
            } catch { self.end(error.localizedDescription); return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 0.5)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer; timer.resume()
        }
    }
    override func broadcastPaused() {
        queue.async { self.systemPaused = true; self.speech?.stop(); self.policy.discardPending() }
    }
    override func broadcastResumed() { queue.async { self.systemPaused = false } }
    override func broadcastFinished() { queue.async { self.cleanUp() } }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        if sampleBufferType == .video {
            // Drop frames BEFORE queuing: retain at most one full screen buffer.
            let now = ProcessInfo.processInfo.systemUptime
            admissionLock.lock()
            let accepted = !videoInFlight && now - lastAdmission >= 1
            if accepted { videoInFlight = true; lastAdmission = now }
            admissionLock.unlock()
            guard accepted else { return }
            queue.async {
                defer {
                    self.admissionLock.lock(); self.videoInFlight = false; self.admissionLock.unlock()
                }
                guard self.running else { return }
                self.state.lastVideoAt = Date()
                guard self.settings.mode == .subtitles, self.canProcess else { return }
                autoreleasepool {
                    do {
                        let text = try self.ocr?.recognize(sampleBuffer, region: self.settings.region) ?? ""
                        self.offer(text)
                    } catch { self.state.message = "Chưa đọc được chữ trong khung hình. Thử vùng phụ đề khác." }
                }
            }
        } else if sampleBufferType == .audioApp {
            queue.async {
                guard self.running else { return }
                self.state.lastAudioAt = Date()
                guard self.settings.mode == .speech, self.canProcess else { return }
                self.speech?.append(sampleBuffer)
            }
        }
        // .audioMic is deliberately ignored. Broadcast picker hides its microphone option.
    }
    private var canProcess: Bool {
        let control = SharedStore.control
        return running && !blocked && !systemPaused && !control.paused && !control.stop && !control.appVisible
    }
    private func offer(_ text: String) {
        guard canProcess else { return }
        let normalized = TranslationPolicy.normalized(text)
        guard normalized.count >= 2 else {
            policy.discardPending()
            currentCandidate = ""
            return
        }
        // Guard against OCR reading our own PiP caption when it intersects the capture region.
        guard !normalized.localizedCaseInsensitiveContains("BÁCH DỊCH"),
              normalized != TranslationPolicy.normalized(state.translation) else { return }
        lastCandidate = Date()
        currentCandidate = normalized
        if normalized == policy.lastSucceeded && !cachedTranslation.isEmpty {
            state.source = normalized
            state.translation = cachedTranslation
            state.translatedAt = Date()
        }
        policy.offer(text)
    }
    private func tick() {
        guard running else { return }
        let control = SharedStore.control
        if control.stop { end("Đã dừng dịch theo yêu cầu."); return }
        if Date().timeIntervalSince(sessionStarted) > 1800 {
            end("Phiên thử đã đủ 30 phút. Bạn có thể mở một phiên mới."); return
        }
        state.paused = control.paused || systemPaused
        if blocked {
            state.message = blockingMessage
            publish()
            return
        }
        if !canProcess {
            policy.discardPending()
            if !previousPaused { speech?.stop() }
            previousPaused = true
            state.source = ""; state.translation = ""; state.translatedAt = nil
            state.message = control.appVisible ? "Quay sang YouTube, TikTok hoặc Douyin để dịch." : "Đang tạm dừng dịch. Chia sẻ màn hình vẫn bật."
        } else {
            previousPaused = false
            if Date().timeIntervalSince(lastCandidate) > 8 {
                policy.discardPending(); state.source = ""; state.translation = ""; state.translatedAt = nil
                if settings.mode == .speech && Date().timeIntervalSince(state.lastAudioAt ?? sessionStarted) > 8 {
                    state.message = "Chưa nhận được tiếng video. Nội dung có thể không cho phép thu âm thanh."
                } else if settings.mode == .subtitles {
                    state.message = "Đang tìm chữ/phụ đề. Thử đổi vùng đọc nếu chưa có kết quả."
                }
            }
            translateNext()
        }
        publish()
    }
    private func translateNext() {
        guard !blocked else { return }
        if policy.reachedLimit {
            state.message = "Đã đạt giới hạn \(settings.sessionLimit) yêu cầu của phiên. Dừng và bắt đầu phiên mới nếu muốn tiếp tục."
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard let text = policy.take(now: now) else { return }
        state.requests = policy.requests
        state.message = "Đang dịch…"
        let token = state.sessionID
        translator?.translate(text, model: settings.model, key: key) { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard self.running, self.state.sessionID == token else { return }
                let finished = ProcessInfo.processInfo.systemUptime
                switch result {
                case .success(let translated):
                    self.policy.complete(text: text, success: true, now: finished)
                    self.cachedTranslation = translated
                    // Do not display a late result after pause/return to app or a long network delay.
                    if self.canProcess && finished - now < 12 && Date().timeIntervalSince(self.lastCandidate) < 8 &&
                       (self.settings.mode == .speech || self.currentCandidate == text) {
                        self.state.source = text; self.state.translation = translated
                        self.state.translatedAt = Date(); self.state.translations += 1
                        self.state.latency = finished - now; self.state.message = "Đang dịch video"
                    }
                case .failure(let error):
                    self.policy.complete(text: text, success: false, now: finished, retryAfter: error.retryAfter)
                    self.state.message = error.message
                    self.blocked = error.fatal
                    if error.fatal { self.blockingMessage = error.message }
                }
                self.publish()
            }
        }
    }
    private func publish() {
        state.updatedAt = Date()
        do { try SharedStore.write(state, to: "snapshot.json") }
        catch { end("Không ghi được dữ liệu dùng chung. Kiểm tra quyền App Group.") }
    }
    private func cleanUp() {
        running = false; timer?.cancel(); timer = nil
        speech?.stop(); speech = nil; translator?.cancel(); translator = nil; ocr = nil; key = ""; cachedTranslation = ""
        state.active = false; state.source = ""; state.translation = ""; state.translatedAt = nil
        state.updatedAt = Date(); state.message = "Phiên dịch đã kết thúc."
        try? SharedStore.write(state, to: "snapshot.json")
    }
    private func end(_ message: String) {
        cleanUp()
        state.message = message
        try? SharedStore.write(state, to: "snapshot.json")
        finishBroadcastWithError(NSError(domain: "BachDichVideo", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: message]))
    }
}
