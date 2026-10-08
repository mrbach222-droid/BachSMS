import XCTest
@testable import RecipientImport

final class RecipientImportTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let encoded = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "xlsx.b64", subdirectory: "Fixtures"))
        let content = try String(contentsOf: encoded)
        let data = try XCTUnwrap(Data(base64Encoded: content, options: .ignoreUnknownCharacters))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testQuotedWindowsCSVWithDuplicatePhones() throws {
        let text = "\u{FEFF}Họ và tên;Số điện thoại\r\n\"Bách, Hà Nội\";0912345678\r\nNgười trùng;+84 912 345 678\r\nBình;909123456.0\r\n"
        let people = RecipientParser.parseLinesFromDelimited(text, delimiter: nil)
        XCTAssertEqual(people.map(\.name), ["Bách, Hà Nội", "Bình"])
        XCTAssertEqual(people.map(\.phone), ["+84912345678", "+84909123456"])
    }

    func testOnlyPhoneHeaderAndInvalidCells() {
        let people = SpreadsheetImporter.parseDelimitedRows([["SDT"], ["0912345678"], ["KH001234567890"], ["=0912345678"]])
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people.first?.name, "anh/chị")
    }

    func testScientificNotationAndDoubleLetterColumns() {
        XCTAssertEqual(RecipientParser.normalizePhone("9.12345678E+8"), "+84912345678")
        XCTAssertEqual(SpreadsheetImporter.columnIndex("Z"), 25)
        XCTAssertEqual(SpreadsheetImporter.columnIndex("AA"), 26)
        XCTAssertEqual(SpreadsheetImporter.columnIndex("AB"), 27)
        XCTAssertNil(RecipientParser.normalizePhone("Khách 0912345678"))
    }

    func testInlineXLSXAfterBlankCoverSheet() throws {
        let file = try fixture("inline-second-sheet")
        let people = try SpreadsheetImporter.parse(url: file)
        XCTAssertEqual(people.map(\.name), ["Lê Ngọc Bách", "Trần Bình"])
        XCTAssertEqual(people.map(\.phone), ["+84912345678", "+84909123456"])
    }

    func testSharedAndRichTextXLSX() throws {
        let file = try fixture("shared-strings")
        let people = try SpreadsheetImporter.parse(url: file)
        XCTAssertEqual(people.map(\.name), ["Lê Ngọc Bách", "Trần Bình"])
        XCTAssertEqual(people.map(\.phone), ["+84912345678", "+84909123456"])
    }

    func testUTF16CSV() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: file) }
        try "Tên,SDT\r\nBách,0912345678\r\n".data(using: .utf16)!.write(to: file)
        let people = try SpreadsheetImporter.parse(url: file)
        XCTAssertEqual(people.first?.name, "Bách")
    }
}
