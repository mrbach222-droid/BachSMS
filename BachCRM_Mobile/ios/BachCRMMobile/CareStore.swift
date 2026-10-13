import Foundation
import SwiftUI

@MainActor
final class CareStore: ObservableObject {
    @Published var customers: [CareCustomer] = []
    @Published var lastSync: Date?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var needsSetup = true

    private var pollTask: Task<Void, Never>?
    private var socketTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?

    init() {
        needsSetup = configuration == nil
    }

    private var configuration: (URL, String)? {
        let raw = SecureSettings.read(SecureSettings.endpointKey)
        let token = SecureSettings.read(SecureSettings.tokenKey)
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil, !token.isEmpty else { return nil }
        return (url, token)
    }

    func configure(endpoint: String, readToken: String) -> Bool {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil,
              readToken.count >= 24 else {
            errorMessage = "Cần địa chỉ HTTPS hợp lệ và mã đọc dữ liệu."
            return false
        }
        stop()
        SecureSettings.save(url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), for: SecureSettings.endpointKey)
        SecureSettings.save(readToken, for: SecureSettings.tokenKey)
        needsSetup = false
        errorMessage = nil
        start()
        return true
    }

    func start() {
        guard !needsSetup, pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                if socketTask == nil { connectChanges() }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
        connectChanges()
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        socketTask?.cancel(); socketTask = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }

    func refresh() async {
        guard let (baseURL, token) = configuration else { needsSetup = true; return }
        let url = baseURL.appendingPathComponent("v1/customers")
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.userAuthenticationRequired)
            }
            let snapshot = try JSONDecoder().decode(CareSnapshot.self, from: data)
            customers = snapshot.customers.sorted {
                if $0.isDue != $1.isDue { return $0.isDue }
                if $0.appointmentDate != $1.appointmentDate {
                    return ($0.appointmentDate ?? "9999") < ($1.appointmentDate ?? "9999")
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            lastSync = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Chưa đồng bộ được. Kiểm tra mạng, địa chỉ hoặc quyền truy cập."
        }
    }

    private func connectChanges() {
        guard socketTask == nil else { return }
        guard let (baseURL, token) = configuration else { return }
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/changes"), resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()
        socketTask = Task {
            while !Task.isCancelled {
                do {
                    _ = try await task.receive()
                    await refresh() // only download authorized, sanitized snapshot
                } catch {
                    break // polling remains an automatic fallback
                }
            }
            if !Task.isCancelled {
                socket = nil
                socketTask = nil // polling loop will reconnect
            }
        }
    }
}