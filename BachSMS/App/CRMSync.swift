import Foundation
import Security
import UIKit

enum CRMSyncConnectionState: Equatable {
    case notConfigured
    case connecting
    case connected
    case offline
    case error(String)
}

enum CRMSyncDeliveryStatus: String, Codable {
    case confirmedSent = "confirmed_sent"
    case skipped
    case failed
}

struct CRMSyncJob: Identifiable, Codable, Hashable {
    let id: String
    let cif: String
    let contractNumber: String?
    let customerName: String
    let phone: String
    let message: String?
    let revision: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case cif
        case contractNumber = "contract_number"
        case customerName = "customer_name"
        case phone
        case message
        case revision
        case createdAt = "created_at"
    }
}

struct CRMSyncSettings: Codable, Equatable {
    var serverURL: String = ""
    var crmCode: String = ""
    var deviceID: String
    var deviceName: String

    static func fresh() -> CRMSyncSettings {
        CRMSyncSettings(
            deviceID: UUID().uuidString.lowercased(),
            deviceName: UIDevice.current.name
        )
    }
}

struct CRMSyncStatusEvent: Identifiable, Codable, Hashable {
    let id: String
    let jobID: String
    let deviceID: String
    let status: CRMSyncDeliveryStatus
    let occurredAt: Date
    let messageFingerprint: String?

    init(
        id: String = UUID().uuidString.lowercased(),
        jobID: String,
        deviceID: String,
        status: CRMSyncDeliveryStatus,
        occurredAt: Date = Date(),
        messageFingerprint: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.deviceID = deviceID
        self.status = status
        self.occurredAt = occurredAt
        self.messageFingerprint = messageFingerprint
    }

    enum CodingKeys: String, CodingKey {
        case id
        case jobID = "job_id"
        case deviceID = "device_id"
        case status
        case occurredAt = "occurred_at"
        case messageFingerprint = "message_fingerprint"
    }
}

private struct CRMPairRequest: Codable {
    let crmCode: String
    let deviceID: String
    let deviceName: String

    enum CodingKeys: String, CodingKey {
        case crmCode = "crm_code"
        case deviceID = "device_id"
        case deviceName = "device_name"
    }
}

private struct CRMPairResponse: Codable {
    let token: String
}

private struct CRMJobsResponse: Codable {
    let jobs: [CRMSyncJob]
    let cursor: String?
}

private struct CRMStatusBatch: Codable {
    let events: [CRMSyncStatusEvent]
}

private struct CRMStatusResponse: Codable {
    let acceptedIDs: [String]

    enum CodingKeys: String, CodingKey {
        case acceptedIDs = "accepted_ids"
    }
}

private enum CRMSyncError: LocalizedError {
    case invalidServerURL
    case notPaired
    case unexpectedResponse
    case server(Int, String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Địa chỉ máy tính chưa hợp lệ. Ví dụ: http://192.168.1.20:8765"
        case .notPaired:
            return "iPhone chưa được ghép với Bách CRM."
        case .unexpectedResponse:
            return "Bách CRM trả về phản hồi không hợp lệ."
        case .server(let code, let message):
            return message.isEmpty ? "Bách CRM báo lỗi mã \(code)." : message
        case .invalidPayload:
            return "Dữ liệu đồng bộ không đúng định dạng."
        }
    }
}

@MainActor
final class CRMSyncController: ObservableObject {
    static let shared = CRMSyncController()

    @Published private(set) var settings: CRMSyncSettings
    @Published private(set) var jobs: [CRMSyncJob] = []
    @Published private(set) var connectionState: CRMSyncConnectionState = .notConfigured
    @Published private(set) var pendingUploadCount = 0
    @Published var lastMessage: String?

    private let defaults: UserDefaults
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let settingsKey = "bach.sms.crm.sync.settings.v1"
    private let outboxKey = "bach.sms.crm.sync.outbox.v1"
    private let tokenService = "vn.ngocbach.bachsms.crm-sync"
    private let tokenAccount = "paired-device-token"
    private var outbox: [CRMSyncStatusEvent] = []

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let data = defaults.data(forKey: settingsKey),
           let saved = try? decoder.decode(CRMSyncSettings.self, from: data) {
            settings = saved
        } else {
            settings = .fresh()
        }

        if let data = defaults.data(forKey: outboxKey),
           let saved = try? decoder.decode([CRMSyncStatusEvent].self, from: data) {
            outbox = saved
            pendingUploadCount = saved.count
        }

        if settings.serverURL.isEmpty || settings.crmCode.isEmpty {
            connectionState = .notConfigured
        } else {
            connectionState = CRMSyncTokenStore.read(
                service: tokenService,
                account: tokenAccount
            ) == nil ? .notConfigured : .offline
        }
    }

    var isPaired: Bool {
        !settings.serverURL.isEmpty
            && !settings.crmCode.isEmpty
            && CRMSyncTokenStore.read(service: tokenService, account: tokenAccount) != nil
    }

    func configure(serverURL: String, crmCode: String, deviceName: String) {
        settings.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        settings.crmCode = crmCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let cleanedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedName.isEmpty {
            settings.deviceName = cleanedName
        }
        persistSettings()
        connectionState = .notConfigured
    }

    func pair() async {
        connectionState = .connecting
        do {
            let url = try endpoint("api/v1/pair")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = try encoder.encode(CRMPairRequest(
                crmCode: settings.crmCode,
                deviceID: settings.deviceID,
                deviceName: settings.deviceName
            ))

            let data = try await perform(request)
            let response = try decoder.decode(CRMPairResponse.self, from: data)
            guard !response.token.isEmpty else { throw CRMSyncError.invalidPayload }
            try CRMSyncTokenStore.write(
                response.token,
                service: tokenService,
                account: tokenAccount
            )
            connectionState = .connected
            lastMessage = "Đã ghép Bách SMS với CRM \(settings.crmCode)."
            await refresh()
        } catch {
            connectionState = .error(error.localizedDescription)
            lastMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard isPaired else {
            connectionState = .notConfigured
            return
        }
        connectionState = .connecting
        do {
            try await flushOutbox()
            var components = URLComponents(url: try endpoint("api/v1/jobs"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "device_id", value: settings.deviceID)
            ]
            guard let url = components?.url else { throw CRMSyncError.invalidServerURL }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            authorize(&request)
            let data = try await perform(request)
            let response = try decoder.decode(CRMJobsResponse.self, from: data)

            var seen = Set<String>()
            jobs = response.jobs
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.createdAt < $1.createdAt }
            connectionState = .connected
            lastMessage = jobs.isEmpty
                ? "CRM chưa giao khách SMS mới."
                : "Đã nhận \(jobs.count) khách từ Bách CRM."
        } catch {
            connectionState = .offline
            lastMessage = "Chưa kết nối được CRM. Dữ liệu gửi sẽ được giữ trong hàng chờ."
        }
    }

    func mark(
        jobID: String,
        status: CRMSyncDeliveryStatus,
        messageFingerprint: String? = nil
    ) {
        guard !jobID.isEmpty else { return }
        let event = CRMSyncStatusEvent(
            jobID: jobID,
            deviceID: settings.deviceID,
            status: status,
            messageFingerprint: messageFingerprint
        )
        if !outbox.contains(where: { $0.id == event.id }) {
            outbox.append(event)
        }
        persistOutbox()
        Task { await flushOutboxIfPossible() }
    }

    func unpair() {
        CRMSyncTokenStore.delete(service: tokenService, account: tokenAccount)
        jobs = []
        connectionState = .notConfigured
        lastMessage = "Đã ngắt ghép nối. Hàng chờ cục bộ vẫn được giữ lại."
    }

    private func flushOutboxIfPossible() async {
        guard isPaired else { return }
        do {
            try await flushOutbox()
            if connectionState != .connecting {
                connectionState = .connected
            }
        } catch {
            connectionState = .offline
        }
    }

    private func flushOutbox() async throws {
        guard !outbox.isEmpty else { return }
        guard isPaired else { throw CRMSyncError.notPaired }

        let sending = outbox
        var request = URLRequest(url: try endpoint("api/v1/statuses"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        authorize(&request)
        request.httpBody = try encoder.encode(CRMStatusBatch(events: sending))

        let data = try await perform(request)
        let response = try decoder.decode(CRMStatusResponse.self, from: data)
        let accepted = Set(response.acceptedIDs)
        guard !accepted.isEmpty else { throw CRMSyncError.invalidPayload }
        outbox.removeAll { accepted.contains($0.id) }
        persistOutbox()
    }

    private func endpoint(_ path: String) throws -> URL {
        guard var base = URL(string: settings.serverURL),
              let scheme = base.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              base.host != nil else {
            throw CRMSyncError.invalidServerURL
        }
        base.appendPathComponent(path)
        return base
    }

    private func authorize(_ request: inout URLRequest) {
        if let token = CRMSyncTokenStore.read(service: tokenService, account: tokenAccount) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(settings.deviceID, forHTTPHeaderField: "X-BachSMS-Device")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CRMSyncError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw CRMSyncError.server(http.statusCode, message)
        }
        return data
    }

    private func persistSettings() {
        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private func persistOutbox() {
        pendingUploadCount = outbox.count
        if let data = try? encoder.encode(outbox) {
            defaults.set(data, forKey: outboxKey)
        }
    }
}

private enum CRMSyncTokenStore {
    static func write(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw CRMSyncError.invalidPayload
        }
        delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Không lưu được khóa ghép nối CRM."]
            )
        }
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
