import Foundation
import Combine
import Speech

final class SessionModel: ObservableObject {
    @Published var settings = SharedStore.settings
    @Published var apiKey = ""
    @Published var snapshot = CaptureSnapshot()
    @Published var issue = ""
    @Published var ready = false
    @Published var speechPermission = "Chưa kiểm tra"
    @Published var previewOnly = false
    @Published var checkingAPI = false
    @Published var pairingCode = ""
    @Published var preparing = false
    let broadcast = BroadcastSession()
    private let host = TranslationHost()
    private var apiCheck: GeminiTranslator?
    private var foreground = true

    init() {
        do { apiKey = try APIKeyStore.load() } catch { issue = error.localizedDescription }
        host.onSnapshot = { [weak self] snapshot in
            guard let self = self, !self.previewOnly else { return }
            self.snapshot = snapshot
            if snapshot.active { self.pairingCode = "" }
        }
        broadcast.onFinished = { [weak self] in self?.captureFinished() }
        setForeground(true)
    }
    var live: Bool { snapshot.isFresh }

    func save() {
        guard !live else { issue = "Dừng phiên hiện tại trước khi đổi cấu hình."; return }
        do {
            guard settings.cloudConsent else { issue = "Cần bật đồng ý gửi chữ đến Gemini để dùng dịch."; return }
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                issue = "Nhập Gemini API key của bạn."; return
            }
            guard settings.model.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil else {
                issue = "Tên model không hợp lệ."; return
            }
            settings.minimumInterval = min(10, max(2, settings.minimumInterval))
            settings.sessionLimit = min(600, max(10, settings.sessionLimit))
            settings.fontSize = min(36, max(20, settings.fontSize))
            try APIKeyStore.save(apiKey)
            try SharedStore.write(settings, to: "settings.json")
            SharedStore.removeSnapshot()
            previewOnly = false; snapshot = CaptureSnapshot()
            preparing = true; ready = false
            host.prepare(settings: settings, key: apiKey, foreground: foreground) { [weak self] result in
                guard let self = self else { return }
                self.preparing = false
                switch result {
                case .success(let code):
                    self.pairingCode = code; self.ready = true
                    self.issue = "Đã lưu API key riêng trong app. Bật khung nổi rồi nhập mã ghép nối 6 số khi được hỏi."
                case .failure(let error): self.issue = error.localizedDescription
                }
            }
        } catch { ready = false; issue = error.localizedDescription }
    }
    func configurationChanged() {
        if ready && !live { host.stop() }
        ready = false; previewOnly = false; pairingCode = ""
    }
    func setForeground(_ visible: Bool) {
        foreground = visible
        host.setForeground(visible)
    }
    func pause(_ paused: Bool) {
        host.pause(paused)
    }
    func stop() {
        previewOnly = false; ready = false
        pairingCode = ""; host.stop(); broadcast.stop()
        issue = "Đang yêu cầu dừng. Nếu biểu tượng chia sẻ màn hình còn sáng, dừng trong Trung tâm điều khiển."
    }
    func demo() {
        guard !live else { return }
        previewOnly = true
        snapshot = CaptureSnapshot()
        snapshot.translation = "Xin chào Bách! Đây là chữ mẫu để kiểm tra khung nổi."
        snapshot.source = "你好！这是悬浮字幕的显示测试。"
        snapshot.message = "Xem thử giao diện · không dịch video"
        // Do not fake an active broadcast or successful real translation.
    }
    var displaySnapshot: CaptureSnapshot {
        guard previewOnly else { return snapshot }
        var sample = snapshot
        sample.active = true; sample.updatedAt = Date(); sample.translatedAt = Date()
        sample.translation = "[CHỮ MẪU] " + sample.translation
        return sample
    }
    func deleteKey() {
        guard !live else { issue = "Dừng phiên trước khi xóa API key."; return }
        do { host.stop(); try APIKeyStore.save(""); apiKey = ""; pairingCode = ""; ready = false; issue = "Đã xóa API key khỏi thiết bị." }
        catch { issue = error.localizedDescription }
    }
    func authorizeSpeech() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.speechPermission = status == .authorized ? "Đã cấp quyền" : "Chưa được cấp quyền"
            }
        }
    }
    func checkAPI() {
        guard !live, !checkingAPI, settings.cloudConsent else {
            issue = "Dừng phiên và bật đồng ý gửi chữ trước khi kiểm tra API."; return
        }
        checkingAPI = true
        let service = GeminiTranslator(); apiCheck = service
        service.translate("Hello, have a nice day.", model: settings.model, key: apiKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checkingAPI = false
                switch result {
                case .success(let text): self.issue = "API hoạt động: \(text)"
                case .failure(let error): self.issue = error.message
                }
                self.apiCheck?.cancel(); self.apiCheck = nil
            }
        }
    }
    private func captureFinished() {
        host.stop(); ready = false; pairingCode = ""
    }
}
