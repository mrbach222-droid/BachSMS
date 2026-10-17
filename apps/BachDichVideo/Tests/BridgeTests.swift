import XCTest
@testable import BachDichCore

final class BridgeTests: XCTestCase {
    func testPairingQRRoundTripThroughVision() throws {
        let image = try XCTUnwrap(PairingQR.image(code: "012345"))
        XCTAssertEqual(try PairingQR.read(image), "012345")
        XCTAssertNil(PairingQR.code(from: "https://example.com/012345"))
        XCTAssertNil(PairingQR.code(from: "BDV-PAIR:1234567"))
        XCTAssertNil(PairingQR.code(from: "BDV-PAIR:１２３４５６"))
    }
    func testPairingRequiresCodeAndCanOnlyHappenOnce() {
        var gate = PairingGate(code: "123456", token: "secret", now: 100)
        XCTAssertFalse(gate.accepts("secret", now: 101))
        XCTAssertNil(gate.pair(code: "000000", now: 101))
        XCTAssertEqual(gate.pair(code: "123456", now: 102), "secret")
        XCTAssertNil(gate.pair(code: "123456", now: 103))
        XCTAssertFalse(gate.accepts("wrong", now: 103))
        XCTAssertTrue(gate.accepts("secret", now: 103))
    }
    func testExpiredCodeAndBruteForceAreRejected() {
        var expired = PairingGate(code: "123456", token: "secret", now: 100)
        XCTAssertNil(expired.pair(code: "123456", now: 220))
        var locked = PairingGate(code: "123456", token: "secret", now: 100)
        for _ in 0..<5 { XCTAssertNil(locked.pair(code: "000000", now: 101)) }
        XCTAssertNil(locked.pair(code: "123456", now: 102))
    }
    func testSessionExpiryAndInvalidation() {
        var gate = PairingGate(code: "123456", token: "secret", now: 100)
        _ = gate.pair(code: "123456", now: 101)
        XCTAssertFalse(gate.accepts("secret", now: 1900))
        gate.invalidate()
        XCTAssertFalse(gate.accepts("secret", now: 102))
    }
    func testNewSessionDoesNotAcceptOldToken() {
        var gate = PairingGate(code: "654321", token: "new-token", now: 100)
        _ = gate.pair(code: "654321", now: 101)
        XCTAssertFalse(gate.accepts("old-token", now: 102))
        XCTAssertTrue(gate.accepts("new-token", now: 102))
    }
    func testHTTPFragmentationPreservesBodyAndAuthorization() {
        let header = "POST /update HTTP/1.1\r\nContent-Length: 2\r\nAuthorization: Bearer abc\r\n\r\n"
        if case .incomplete = BridgeHTTPRequest.parse(Data((header + "{").utf8)) {} else { XCTFail("Partial body must wait") }
        guard case .complete(let request) = BridgeHTTPRequest.parse(Data((header + "{}").utf8)) else {
            XCTFail("Valid bounded request should parse"); return
        }
        XCTAssertEqual(request.path, "/update")
        XCTAssertEqual(request.token, "abc")
        XCTAssertEqual(request.body, Data("{}".utf8))
    }
    func testRejectsSmugglingOversizeAndTranscriptReadRequests() {
        let requests = [
            "POST /update HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}",
            "POST /update HTTP/1.1\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n{}",
            "POST /update HTTP/1.1\r\nContent-Length: 9000\r\n\r\n",
            "POST /update HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}trailing",
            "GET /update HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
            "POST /transcript HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
            String(repeating: "x", count: 16385)
        ]
        for request in requests {
            if case .rejected = BridgeHTTPRequest.parse(Data(request.utf8)) {} else { XCTFail("Unsafe request accepted") }
        }
    }
    func testPairingResponseHasNoAPIKeyOrTranscript() throws {
        let reply = BridgeReply(ok: true, token: "session-token", settings: AppSettings(), command: BridgeCommand())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reply)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["ok", "message", "token", "settings", "command"])
        let settings = try XCTUnwrap(json["settings"] as? [String: Any])
        XCTAssertNil(settings["apiKey"])
        XCTAssertNil(json["translation"])
        XCTAssertNil(json["source"])
    }

    /// Exercises real TCP + URLSession, not a mock transport. No Google request is made.
    func testLoopbackPairUpdateFinishRoundTrip() throws {
        let queue = DispatchQueue(label: "BachDich.bridge-test")
        var gate = PairingGate(code: "123456", token: "session-token", now: 100)
        let server = LocalHTTPServer(queue: queue) { request in
            if request.path == "/pair" {
                let body = (try? JSONDecoder().decode([String: String].self, from: request.body)) ?? [:]
                guard let token = gate.pair(code: body["code"] ?? "", now: 101) else { return BridgeReply(ok: false) }
                return BridgeReply(ok: true, token: token, settings: AppSettings(), command: BridgeCommand())
            }
            guard gate.accepts(request.token, now: 102) else { return BridgeReply(ok: false, command: BridgeCommand(stop: true)) }
            if request.path == "/finish" { gate.invalidate() }
            return BridgeReply(ok: true, command: BridgeCommand(appVisible: false))
        }
        defer { queue.sync { server.stop() } }
        let ready = expectation(description: "Loopback listener ready")
        try server.start { success in XCTAssertTrue(success); ready.fulfill() }
        wait(for: [ready], timeout: 5)
        let client = BridgeClient()
        defer { client.close() }
        func post(_ body: [String: String], _ path: String, token: String = "") throws -> BridgeReply {
            let done = expectation(description: path)
            var result: Result<BridgeReply, Error>?
            client.post(body, path: path, token: token) { value in result = value; done.fulfill() }
            wait(for: [done], timeout: 6)
            return try XCTUnwrap(result).get()
        }
        XCTAssertFalse(try post(["code": "000000"], "/pair").ok)
        let paired = try post(["code": "123456"], "/pair")
        XCTAssertTrue(paired.ok)
        let token = try XCTUnwrap(paired.token)
        XCTAssertFalse(try post(["code": "123456"], "/pair").ok)
        XCTAssertFalse(try post([:], "/update").ok)
        let command = try post(["text": "你好"], "/update", token: token)
        XCTAssertTrue(command.ok)
        XCTAssertEqual(command.command?.appVisible, false)
        XCTAssertTrue(try post([:], "/finish", token: token).ok)
        XCTAssertFalse(try post([:], "/update", token: token).ok)
    }
}
