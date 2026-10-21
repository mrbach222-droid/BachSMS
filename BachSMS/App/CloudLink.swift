import Foundation

struct CloudLink: Codable {
    let url: String
    let channel: String
    let token: String

    static func parse(_ input: String) throws -> CloudLink {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix("bachsms1."), code.count < 4096 else { throw CloudLinkError.invalidCode }
        var value = String(code.dropFirst(9)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value),
              let link = try? JSONDecoder().decode(CloudLink.self, from: data),
              let components = URLComponents(string: link.url), components.scheme == "https",
              components.host != nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              UUID(uuidString: link.channel) != nil,
              link.token.range(of: "^r_[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw CloudLinkError.invalidCode
        }
        return link
    }
}

enum CloudLinkError: LocalizedError {
    case invalidCode
    var errorDescription: String? { "Mã Cloudflare chưa hợp lệ. Sao chép đầy đủ mã bắt đầu bằng bachsms1. từ CRM trên PC." }
}
