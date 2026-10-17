import Foundation

enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    case subtitles, speech
    var id: String { rawValue }
    var title: String { self == .subtitles ? "Chữ / phụ đề" : "Lời nói · thử nghiệm" }
}

enum SubtitleRegion: String, Codable, CaseIterable, Identifiable {
    case middle, lower, upper
    var id: String { rawValue }
    var title: String {
        switch self { case .middle: return "Giữa màn hình"
        case .lower: return "Nửa dưới"; case .upper: return "Nửa trên" }
    }
    // Vision coordinates: origin is bottom-left. Avoid top status bar and bottom navigation.
    var bounds: (x: Double, y: Double, width: Double, height: Double) {
        switch self {
        case .middle: return (0.04, 0.18, 0.82, 0.62)
        case .lower: return (0.04, 0.10, 0.82, 0.44)
        case .upper: return (0.04, 0.48, 0.82, 0.42)
        }
    }
}

struct AppSettings: Codable, Equatable {
    var mode: CaptureMode = .subtitles
    var region: SubtitleRegion = .middle
    var speechLocale = "zh-CN"
    var model = "gemini-flash-latest"
    var cloudConsent = false
    var showOriginal = true
    var fontSize: Double = 28
    var minimumInterval: Double = 3
    var sessionLimit = 120
    static let speechLanguages = ["zh-CN": "Trung Quốc", "en-US": "Tiếng Anh",
                                  "ja-JP": "Tiếng Nhật", "ko-KR": "Tiếng Hàn"]
}

struct CaptureControl: Codable {
    var paused = false
    var stop = false
    var appVisible = true
}

struct CaptureSnapshot: Codable, Equatable {
    var sessionID = UUID().uuidString
    var active = false
    var paused = false
    var updatedAt = Date()
    var lastVideoAt: Date?
    var lastAudioAt: Date?
    var source = ""
    var translation = ""
    var translatedAt: Date?
    var message = "Chưa bắt đầu"
    var requests = 0
    var translations = 0
    var latency: Double = 0
    var isFresh: Bool { active && Date().timeIntervalSince(updatedAt) < 12 }
}
