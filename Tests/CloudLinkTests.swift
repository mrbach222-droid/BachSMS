import XCTest
@testable import RecipientImport

final class CloudLinkTests: XCTestCase {
    private func code(_ url: String, _ token: String = "r_" + String(repeating: "a", count: 64)) throws -> String {
        let data = try JSONEncoder().encode(CloudLink(url: url, channel: "12345678-1234-1234-1234-123456789abc", token: token))
        return "bachsms1." + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func testCloudPairing() throws {
        XCTAssertEqual(try CloudLink.parse(code("https://example.workers.dev")).url, "https://example.workers.dev")
        XCTAssertThrowsError(try CloudLink.parse(code("http://example.workers.dev")))
        XCTAssertThrowsError(try CloudLink.parse(code("https://user:password@example.com")))
        XCTAssertThrowsError(try CloudLink.parse(code("https://example.com/path")))
        XCTAssertThrowsError(try CloudLink.parse(code("https://example.com?token=x")))
        XCTAssertThrowsError(try CloudLink.parse(code("https://example.com", "w_" + String(repeating: "a", count: 64))))
        XCTAssertThrowsError(try CloudLink.parse("bachsms1.invalid"))
    }
}
