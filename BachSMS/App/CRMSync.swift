import Foundation
import Security
import UIKit
import CryptoKit

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
    private var scopedOutboxKey: String { isCloud ? outboxKey + "." + scopeHash : outboxKey }
    private var scopeHash: String { SHA256.hash(data: Data((settings.serverURL + "|" + settings.crmCode).utf8)).map { String(format: "%02x", $0) }.joined() }
    var isCloud: Bool { settings.crmCode.hasPrefix("CF-") }
    private var inboxURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BachSMSCloud").appendingPathComponent(scopeHash + ".json")
    }
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

        if let data = defaults.data(forKey: scopedOutboxKey),
           let saved = try? decoder.decode([CRMSyncStatusEvent].self, from: data) {
            outbox = saved
            pendingUploadCount = saved.count
        }
        if isCloud, let data = try? Data(contentsOf: inboxURL),
           let saved = try? decoder.decode([CRMSyncJob].self, from: data) { jobs = saved }

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
        persistOutbox()
        settings.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        settings.crmCode = crmCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let cleanedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedName.isEmpty {
            settings.deviceName = cleanedName
        }
        persistSettings()
        outbox = (defaults.data(forKey: scopedOutboxKey).flatMap { try? decoder.decode([CRMSyncStatusEvent].self, from: $0) }) ?? []
        pendingUploadCount = outbox.count
        connectionState = .notConfigured
    }

    func linkCloud(_ code: String) async {
        connectionState = .connecting
        do {
            let link = try CloudLink.parse(code)
            var request = URLRequest(url: URL(string: link.url)!.appendingPathComponent("api/v1/jobs"))
            request.timeoutInterval = 20
            request.setValue("Bearer " + link.token, forHTTPHeaderField: "Authorization")
            _ = try decoder.decode(CRMJobsResponse.self, from: await perform(request))
            persistOutbox()
            try CRMSyncTokenStore.write(link.token, service: tokenService, account: tokenAccount)
            settings.serverURL = link.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            settings.crmCode = "CF-" + link.channel
            persistSettings()
            outbox = defaults.data(forKey: scopedOutboxKey).flatMap { try? decoder.decode([CRMSyncStatusEvent].self, from: $0) } ?? []
            pendingUploadCount = outbox.count
            jobs = (try? Data(contentsOf: inboxURL)).flatMap { try? decoder.decode([CRMSyncJob].self, from: $0) } ?? []
            await refresh()
        } catch {
            connectionState = .error(error.localizedDescription)
            lastMessage = error.localizedDescription
        }
    }

    private func saveCloudInbox(_ incoming: [CRMSyncJob]) throws {
        var byID = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        for job in incoming { byID[job.id] = job }
        let saved = byID.values.sorted { $0.createdAt < $1.createdAt }
        try FileManager.default.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(saved).write(to: inboxURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        jobs = saved
    }

    private func receiveCloudJobs() async throws {
        var pages = 0
        while pages < 250 {
            pages += 1
            var request = URLRequest(url: try endpoint("api/v1/jobs"))
            request.timeoutInterval = 20
            authorize(&request)
            let response = try decoder.decode(CRMJobsResponse.self, from: await perform(request))
            if response.jobs.isEmpty { break }
            // The server may erase personal fields only after this atomic local save succeeds.
            try saveCloudInbox(response.jobs)
            var ack = URLRequest(url: try endpoint("api/v1/received"))
            ack.httpMethod = "POST"; ack.timeoutInterval = 20
            ack.setValue("application/json", forHTTPHeaderField: "Content-Type")
            authorize(&ack)
            ack.httpBody = try JSONSerialization.data(withJSONObject: ["job_ids": response.jobs.map(\.id)])
            _ = try await perform(ack)
        }
        connectionState = .connected
        lastMessage = "Đã lưu \(jobs.count) khách trên iPhone. Có thể dùng danh sách khi mất mạng."
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
            if isCloud { try await receiveCloudJobs(); return }
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
            lastMessage = "Chưa kết nối được CRM: \(error.localizedDescription). Danh sách đã nhận và trạng thái chờ vẫn được giữ trên máy."
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

        let sending = Array(outbox.prefix(20))
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
        if !outbox.isEmpty { try await flushOutbox() }
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
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["error"] as? String ?? String(data: data, encoding: .utf8) ?? ""
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
            defaults.set(data, forKey: scopedOutboxKey)
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

