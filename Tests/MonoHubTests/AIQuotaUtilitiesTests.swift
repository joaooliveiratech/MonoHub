import Foundation
import Testing
@testable import MonoHub

@Suite("Utilities & Parsing Tests")
struct UtilitiesTests {
    @Test("ISO8601 date parsing whole and fractional")
    func testISO8601DateParsing() {
        let whole = "2026-10-01T12:00:00Z"
        let parsedWhole = ISO8601.date(from: whole)
        #expect(parsedWhole != nil)

        let fractional = "2026-10-01T12:00:00.123Z"
        let parsedFractional = ISO8601.date(from: fractional)
        #expect(parsedFractional != nil)

        let empty = ISO8601.date(from: "")
        #expect(empty == nil)

        let invalid = ISO8601.date(from: "not-a-date")
        #expect(invalid == nil)
    }

    @Test("FlexibleNumber parses numbers and strings")
    func testFlexibleNumberParsing() {
        let fromNum = FlexibleNumber.double(NSNumber(value: 42.5))
        #expect(fromNum == 42.5)

        let fromStr = FlexibleNumber.double("  99.9  ")
        #expect(fromStr == 99.9)

        let fromInvalid = FlexibleNumber.double("invalid")
        #expect(fromInvalid == nil)

        let fromNil = FlexibleNumber.double(nil)
        #expect(fromNil == nil)
    }

    @Test("URLRequest extensions set headers cleanly")
    func testURLRequestExtensions() {
        let url = URL(string: "https://api.test.com/v1")!
        var req = URLRequest.get(url, timeout: 5.0)
        #expect(req.httpMethod == "GET")
        #expect(req.timeoutInterval == 5.0)

        req.setBearer("test-token-123")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-123")

        let post = URLRequest.postJSON(url, body: Data("{}".utf8), timeout: 5.0)
        #expect(post.httpMethod == "POST")
        #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}
