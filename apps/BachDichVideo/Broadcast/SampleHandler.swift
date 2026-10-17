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

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.async {
            guard let token = setupInfo?["token"] as? String, token.count >= 64,
                  let encoded = setupInfo?["settings"] as? String,
                  let data = Data(base64Encoded: encoded), data.count < 8192,
                  let settings = try? JSONDecoder().decode(AppSettings.self, from: data), settings.cloudConsent else {
                self.end("Mở Bách Dịch Video, lấy mã và dùng nút Ghép nối / bắt đầu trong app. Không bắt đầu trực tiếp từ Trung tâm điều khiển."); return
            }
            self.token = token; self.settings = settings; self.running = true
            self.client = BridgeClient(); self.ocr = ScreenOCR()
            if settings.mode == .speech {
                self.speech = DeviceSpeech(locale: settings.speechLocale, queue: self.queue,
                    output: { [weak self] text in self?.update.text = text },
                    status: { [weak self] status in self?.update.speechStatus = status })
            }
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
            self.client?.post(["done": true], path: "/finish", token: self.token) { _ in }
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
