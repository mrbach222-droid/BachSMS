import Foundation
import Speech
import CoreMedia

/// Experimental: ReplayKit app audio only, never opens the microphone.
/// All calls and callbacks are confined to the supplied serial queue.
final class DeviceSpeech {
    private let queue: DispatchQueue
    private let locale: String
    private let output: (String) -> Void
    private let status: (String) -> Void
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var started = Date.distantPast
    private var nextStart = Date.distantPast
    private var generation = UUID()
    private var emitted = ""

    init(locale: String, queue: DispatchQueue, output: @escaping (String) -> Void,
         status: @escaping (String) -> Void) {
        self.locale = locale; self.queue = queue; self.output = output; self.status = status
    }
    func append(_ sample: CMSampleBuffer) {
        if request != nil && Date().timeIntervalSince(started) > 40 { stop() }
        if request == nil { start() }
        request?.appendAudioSampleBuffer(sample)
    }
    private func start() {
        guard Date() >= nextStart else { return }
        nextStart = Date().addingTimeInterval(5)
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            status("Chưa cấp quyền nhận dạng lời nói. Dừng phiên và cấp quyền trong app."); return
        }
        guard let engine = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              engine.isAvailable, engine.supportsOnDeviceRecognition else {
            status("Máy chưa hỗ trợ nhận dạng tại chỗ cho ngôn ngữ này. Thử ngôn ngữ khác hoặc chế độ phụ đề."); return
        }
        recognizer = engine
        let input = SFSpeechAudioBufferRecognitionRequest()
        input.requiresOnDeviceRecognition = true
        input.shouldReportPartialResults = true
        input.taskHint = .dictation
        request = input; started = Date(); emitted = ""
        let token = UUID(); generation = token
        task = engine.recognitionTask(with: input) { [weak self] result, error in
            guard let self = self else { return }
            self.queue.async {
                guard self.generation == token else { return }
                if let result = result {
                    // Publish complete recent segments rather than repeating an ever-growing transcript.
                    let segments = result.bestTranscription.segments
                    let recent = segments.filter { $0.timestamp >= max(0, (segments.last?.timestamp ?? 0) - 7) }
                    let text = recent.map(\.substring).joined(separator: " ")
                    if text != self.emitted && text.count >= 2 {
                        self.emitted = text; self.output(text)
                    }
                    if result.isFinal { self.stop() }
                }
                if error != nil {
                    self.stop()
                    self.nextStart = Date().addingTimeInterval(5)
                    self.status("Nhận dạng lời nói bị ngắt. Đang chờ thử lại; có thể dùng chế độ phụ đề.")
                }
            }
        }
    }
    func stop() {
        generation = UUID()
        request?.endAudio(); task?.cancel()
        task = nil; request = nil; recognizer = nil
    }
}
