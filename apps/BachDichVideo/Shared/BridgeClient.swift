import Foundation

final class BridgeClient {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.urlCache = nil
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
    }
    func post<T: Encodable>(_ value: T, path: String, token: String = "",
                           completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        guard ["/pair", "/update", "/finish"].contains(path),
              let url = URL(string: LocalBridge.origin + path) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        do { request.httpBody = try JSONEncoder().encode(value) }
        catch { completion(.failure(error)); return }
        session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data, data.count < 16_384,
                  let reply = try? JSONDecoder().decode(BridgeReply.self, from: data) else {
                completion(.failure(NSError(domain: "BachBridge", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Không nhận được phản hồi từ app chính."]))); return
            }
            completion(.success(reply))
        }.resume()
    }
    func close() { session.invalidateAndCancel() }
}
