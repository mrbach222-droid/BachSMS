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
    private var apiCheck: GeminiTranslator?
    private var timer: Timer?
    private var foreground = true

    init() {
        do { apiKey = try APIKeyStore.load() } catch { issue = error.localizedDescription }
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        setForeground(true)
    }
    deinit { timer?.invalidate() }
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
            try SharedStore.write(CaptureControl(paused: false, stop: false, appVisible: foreground), to: "control.json")
            SharedStore.removeSnapshot()
            previewOnly = false; snapshot = CaptureSnapshot()
            issue = "Đã lưu. Bật khung nổi, rồi bấm Chia sẻ màn hình."
            ready = true
        } catch { ready = false; issue = error.localizedDescription }
    }
    func configurationChanged() { ready = false; previewOnly = false }
    func setForeground(_ visible: Bool) {
        foreground = visible
        var control = SharedStore.control
        control.appVisible = visible
        do { try SharedStore.write(control, to: "control.json") }
        catch { issue = error.localizedDescription }
    }
    func pause(_ paused: Bool) {
        var control = SharedStore.control; control.paused = paused
        do { try SharedStore.write(control, to: "control.json") }
        catch { issue = error.localizedDescription }
    }
    func stop() {
        previewOnly = false; ready = false
        var control = SharedStore.control; control.stop = true; control.paused = true
        do { try SharedStore.write(control, to: "control.json") }
        catch { issue = error.localizedDescription }
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
        do { try APIKeyStore.save(""); apiKey = ""; ready = false; issue = "Đã xóa API key khỏi thiết bị." }
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
    private func poll() {
        guard !previewOnly else { return }
        if let fresh = SharedStore.snapshot {
            snapshot = fresh
            if !fresh.active { ready = false }
            if fresh.active && Date().timeIntervalSince(fresh.updatedAt) > 60 {
                snapshot.source = ""; snapshot.translation = ""; snapshot.translatedAt = nil
                SharedStore.removeSnapshot()
                ready = false
            }
        }
    }
}
