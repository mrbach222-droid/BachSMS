import ReplayKit
@preconcurrency import CoreMedia
import Foundation

/// Sends recognized TEXT to the paired host. No App Groups or API keys here.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "vn.bach.dich.capture")
    private let lock = NSLock()
    private var videoInFlight = false
    private var lastAdmission: TimeInterval = 0
    private var settings = AppSettings()
    private var command = BridgeCommand()
    private var update = BridgeUpdate()
    private var ocr: ScreenOCR?
    private var speech: DeviceSpeech?
    private var client: BridgeClient?
    private var timer: DispatchSourceTimer?
    private var token = ""
    private var running = false
    private var sending = false
    private var failures = 0
    private var wasPaused = true
    private var pairing = false
    private var began = Date()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.async {
            self.running = true; self.began = Date()
            self.client = BridgeClient(); self.ocr = ScreenOCR()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1)
            timer.setEventHandler { [weak self] in self?.sendUpdate() }
            self.timer = timer; timer.resume()
        }
    }
    override func broadcastPaused() { queue.async { self.command.paused = true; self.speech?.stop() } }
    override func broadcastResumed() { queue.async { self.command.paused = false } }
    override func broadcastFinished() {
        queue.async {
            if !self.token.isEmpty { self.client?.post(["done": true], path: "/finish", token: self.token) { _ in } }
            self.cleanup()
        }
    }
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        if sampleBufferType == .video {
            let now = ProcessInfo.processInfo.systemUptime
            lock.lock()
            let accept = !videoInFlight && now - lastAdmission >= 1
            if accept { videoInFlight = true; lastAdmission = now }
            lock.unlock()
            guard accept else { return }
            queue.async {
                defer { self.lock.lock(); self.videoInFlight = false; self.lock.unlock() }
                guard self.running else { return }
                if self.token.isEmpty {
                    if !self.pairing, let code = try? self.ocr?.pairingCode(sampleBuffer) { self.pair(code) }
                    return
                }
                self.update.videoAt = Date()
                guard self.settings.mode == .subtitles, self.canProcess else { return }
                autoreleasepool {
                    do { self.update.text = try self.ocr?.recognize(sampleBuffer, region: self.settings.region) ?? "" }
                    catch { self.update.speechStatus = "Chưa đọc được chữ trong khung hình." }
                }
            }
        } else if sampleBufferType == .audioApp {
            queue.async {
                guard self.running else { return }
                self.update.audioAt = Date()
                guard self.settings.mode == .speech, self.canProcess else { return }
                self.speech?.append(sampleBuffer)
            }
        }
    }
    private var canProcess: Bool { running && !command.paused && !command.stop && !command.appVisible }
    private func sendUpdate() {
        guard running, !sending else { return }
        guard !token.isEmpty else {
            if Date().timeIntervalSince(began) > 45 { end("Chưa nối được app chính. Dừng chia sẻ, mở app bấm Lưu, bật khung nổi và giữ mã QR hiện khi bắt đầu lại.") }
            return
        }
        sending = true
        let payload = update
        update.text = nil; update.speechStatus = nil
        client?.post(payload, path: "/update", token: token) { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                self.sending = false
                guard self.running else { return }
                switch result {
                case .success(let reply):
                    self.failures = 0
                    guard reply.ok, let command = reply.command, !command.stop else {
                        self.end(reply.message.isEmpty ? "Phiên dịch đã kết thúc." : reply.message); return
                    }
                    self.command = command
                    let paused = command.paused || command.appVisible
                    if paused && !self.wasPaused { self.speech?.stop(); self.update.text = nil }
                    self.wasPaused = paused
                case .failure:
                    self.failures += 1
                    if self.failures >= 4 { self.end("Mất kết nối với app chính. Mở app, bật khung nổi và bắt đầu phiên mới.") }
                }
            }
        }
    }
    private func pair(_ code: String) {
        pairing = true
        client?.post(["code": code], path: "/pair") { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard self.running else { return }
                self.pairing = false
                switch result {
                case .success(let reply):
                    guard reply.ok, let token = reply.token, token.count >= 64,
                          let settings = reply.settings, settings.cloudConsent else {
                        self.end("Mã ghép nối đã hết hạn hoặc đã dùng. Bấm Lưu trong app để tạo mã mới rồi bắt đầu lại."); return
                    }
                    self.token = token; self.settings = settings
                    self.command = reply.command ?? BridgeCommand()
                    if settings.mode == .speech {
                        self.speech = DeviceSpeech(locale: settings.speechLocale, queue: self.queue,
                            output: { [weak self] text in self?.update.text = text },
                            status: { [weak self] status in self?.update.speechStatus = status })
                    }
                case .failure:
                    self.failures += 1
                    if self.failures >= 4 { self.end("Không kết nối được app chính. Mở app, bật khung nổi rồi thử lại.") }
                }
            }
        }
    }
    private func cleanup() {
        running = false; timer?.cancel(); timer = nil
        speech?.stop(); speech = nil; ocr = nil; token = ""
        client = nil; update = BridgeUpdate()
    }
    private func end(_ message: String) {
        cleanup()
        finishBroadcastWithError(NSError(domain: "BachDichVideo", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]))
    }
}
