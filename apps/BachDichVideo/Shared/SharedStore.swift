import Foundation

enum SharedStore {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "SharedGroup") as? String ?? "" }
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }

    static func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = container?.appendingPathComponent(name),
              let data = try? Data(contentsOf: url), data.count < 64_000 else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, to name: String) throws {
        guard let root = container else { throw StoreError.noGroup }
        let data = try JSONEncoder().encode(value)
        try data.write(to: root.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        var resource = root.appendingPathComponent(name)
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try resource.setResourceValues(flags)
    }
    static func removeSnapshot() {
        guard let url = container?.appendingPathComponent("snapshot.json") else { return }
        try? FileManager.default.removeItem(at: url)
    }
    static var settings: AppSettings { read("settings.json", as: AppSettings.self) ?? AppSettings() }
    static var control: CaptureControl { read("control.json", as: CaptureControl.self) ?? CaptureControl() }
    static var snapshot: CaptureSnapshot? { read("snapshot.json", as: CaptureSnapshot.self) }
}

enum StoreError: LocalizedError {
    case noGroup, keychain(Int32)
    var errorDescription: String? {
        switch self {
        case .noGroup: return "Chưa có quyền App Group. Cần ký đúng cấu hình cho app và extension."
        case .keychain(let code): return "Không truy cập được khóa API (Keychain \(code)). Kiểm tra chữ ký và quyền dùng chung."
        }
    }
}
