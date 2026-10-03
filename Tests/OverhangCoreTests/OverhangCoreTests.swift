@testable import OverhangCore
import XCTest

final class CalculatorTests: XCTestCase {
    func eval(_ s: String) throws -> Double { try Calculator.evaluate(s) }

    func testPrecedenceAndParentheses() throws {
        XCTAssertEqual(try eval("1 + 2 * 3"), 7)
        XCTAssertEqual(try eval("(1 + 2) * 3"), 9)
        XCTAssertEqual(try eval("2 ^ 3 ^ 2"), 512) // right associative
        XCTAssertEqual(try eval("-2 ^ 2"), -4)
        XCTAssertEqual(try eval("10 % 4"), 2)
        XCTAssertEqual(try eval("7 / 2"), 3.5)
    }

    func testFunctionsConstantsAndImplicitMultiplication() throws {
        XCTAssertEqual(try eval("sqrt(16)"), 4)
        XCTAssertEqual(try eval("2pi"), 2 * Double.pi, accuracy: 1e-12)
        XCTAssertEqual(try eval("3(1+1)"), 6)
        XCTAssertEqual(try eval("sin(pi/2)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try eval("log(1000)"), 3, accuracy: 1e-12)
        XCTAssertEqual(try eval("1e3 + 1"), 1001)
        XCTAssertEqual(try eval("6 × 7 ÷ 2"), 21)
    }

    func testErrors() {
        XCTAssertThrowsError(try eval("1 +"))
        XCTAssertThrowsError(try eval("foo(2)"))
        XCTAssertThrowsError(try eval("(1 + 2"))
        XCTAssertThrowsError(try eval("1 / 0"))
        XCTAssertThrowsError(try eval("2 $ 3"))
    }

    func testFormatting() throws {
        XCTAssertEqual(Calculator.format(try eval("0.1 + 0.2")), "0.3")
        XCTAssertEqual(Calculator.format(42), "42")
        XCTAssertEqual(Calculator.format(-3.5), "-3.5")
    }
}

final class UnitConverterTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(UnitConverter.parse("12 km to mi"), ConversionQuery(value: 12, from: "km", to: "mi"))
        XCTAssertEqual(UnitConverter.parse("1,000usd in eur"), ConversionQuery(value: 1000, from: "usd", to: "eur"))
        XCTAssertEqual(UnitConverter.parse("-40 c = f"), ConversionQuery(value: -40, from: "c", to: "f"))
        XCTAssertEqual(UnitConverter.parse("3 ft in in"), ConversionQuery(value: 3, from: "ft", to: "in"))
        XCTAssertNil(UnitConverter.parse("hello"))
    }

    func testConversions() throws {
        let km = try XCTUnwrap(UnitConverter.unit(named: "km"))
        let mi = try XCTUnwrap(UnitConverter.unit(named: "miles"))
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(1.609344, from: km, to: mi)), 1, accuracy: 1e-9)

        let c = try XCTUnwrap(UnitConverter.unit(named: "°C"))
        let f = try XCTUnwrap(UnitConverter.unit(named: "f"))
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(-40, from: c, to: f)), -40, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(100, from: c, to: f)), 212, accuracy: 1e-9)

        let result = try XCTUnwrap(UnitConverter.evaluate(XCTUnwrap(UnitConverter.parse("2 lb to kg"))))
        XCTAssertEqual(result.value, 0.90718474, accuracy: 1e-9)

        XCTAssertNil(UnitConverter.convert(1, from: km, to: c))
        XCTAssertEqual(UnitConverter.unit(named: "MB")?.symbol, "MB")
        XCTAssertEqual(UnitConverter.unit(named: "metres")?.symbol, "m")
        XCTAssertEqual(UnitConverter.unit(named: "degrees fahrenheit")?.symbol, "°F")
    }

    func testCurrency() throws {
        let rates = ["USD": 1, "EUR": 0.5, "INR": 80]
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convertCurrency(10, from: "usd", to: "eur", rates: rates)), 5)
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convertCurrency(5, from: "EUR", to: "INR", rates: rates)), 800)
        XCTAssertNil(UnitConverter.convertCurrency(5, from: "XYZ", to: "INR", rates: rates))
        XCTAssertEqual(UnitConverter.currencyCode("€"), "EUR")
    }
}

final class TimerLogicTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(DurationFormatter.clock(65), "1:05")
        XCTAssertEqual(DurationFormatter.clock(3725), "1:02:05")
        XCTAssertEqual(DurationFormatter.clock(-3), "0:00")
        XCTAssertEqual(DurationFormatter.clock(0.2), "0:01")
        XCTAssertEqual(DurationFormatter.short(1500), "25m")
        XCTAssertEqual(DurationFormatter.short(3900), "1h 5m")
    }

    func testParse() {
        XCTAssertEqual(DurationFormatter.parse("5"), 300)
        XCTAssertEqual(DurationFormatter.parse("90s"), 90)
        XCTAssertEqual(DurationFormatter.parse("1h30m"), 5400)
        XCTAssertEqual(DurationFormatter.parse("1:30"), 90)
        XCTAssertNil(DurationFormatter.parse("abc"))
        XCTAssertNil(DurationFormatter.parse("0"))
    }

    func testPomodoroCycle() {
        var cycle = PomodoroCycle(sessionsBeforeLongBreak: 2)
        XCTAssertEqual(cycle.phase, .work)
        XCTAssertEqual(cycle.advance(), .shortBreak)
        XCTAssertEqual(cycle.advance(), .work)
        XCTAssertEqual(cycle.advance(), .longBreak)
        XCTAssertEqual(cycle.advance(), .work)
        XCTAssertEqual(cycle.duration(work: 25, shortBreak: 5, longBreak: 15), 25)
    }
}

final class UsageLogParserTests: XCTestCase {
    func testClaudeCodeLine() throws {
        let line = #"{"type":"assistant","requestId":"req_1","timestamp":"2026-10-01T10:00:00.123Z","message":{"id":"msg_1","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}"#
        let parsed = try XCTUnwrap(UsageLogParser.parseClaudeCodeLine(line))
        XCTAssertEqual(parsed.key, "msg_1:req_1")
        XCTAssertEqual(parsed.record.billableTokens, 60)
        XCTAssertEqual(parsed.record.totalTokens, 100)
        XCTAssertEqual(parsed.record.model, "claude-sonnet-4-5")
        XCTAssertNil(UsageLogParser.parseClaudeCodeLine(#"{"type":"user","message":{"content":"hi"}}"#))
    }

    func testCodexLine() throws {
        let line = #"{"timestamp":"2026-10-01T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":5,"total_tokens":105}}}}"#
        let record = try XCTUnwrap(UsageLogParser.parseCodexLine(line, model: "gpt-5"))
        XCTAssertEqual(record.inputTokens, 40)
        XCTAssertEqual(record.cacheReadTokens, 60)
        XCTAssertEqual(record.outputTokens, 5)
        XCTAssertNil(UsageLogParser.parseCodexLine(#"{"timestamp":"2026-10-01T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#))
    }

    func testSummaryWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func record(hoursAgo: Double, tokens: Int, model: String = "a") -> UsageRecord {
            UsageRecord(source: .claudeCode, model: model, timestamp: now.addingTimeInterval(-hoursAgo * 3600),
                        inputTokens: tokens, outputTokens: 0)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let summary = UsageLogParser.summarize(
            [record(hoursAgo: 1, tokens: 10), record(hoursAgo: 6, tokens: 20, model: "b"), record(hoursAgo: 24 * 8, tokens: 99)],
            now: now, calendar: calendar
        )
        XCTAssertEqual(summary.last5Hours.billableTokens, 10)
        XCTAssertEqual(summary.last7Days.billableTokens, 30)
        XCTAssertEqual(summary.byModel.first?.model, "b")
        XCTAssertEqual(UsageLogParser.compactCount(1500), "1.5K")
    }
}

final class EmojiAndWeatherTests: XCTestCase {
    func testEmojiCatalog() {
        XCTAssertGreaterThan(EmojiCatalog.all.count, 900)
        XCTAssertTrue(EmojiCatalog.search("grinning").contains { $0.character == "😀" })
        XCTAssertTrue(EmojiCatalog.search("red heart").isEmpty == false || EmojiCatalog.search("heart").isEmpty == false)
        XCTAssertEqual(Set(EmojiCatalog.all.map(\.character)).count, EmojiCatalog.all.count)
    }

    func testWeatherCodes() {
        XCTAssertEqual(WeatherCode.describe(0), "Clear")
        XCTAssertEqual(WeatherCode.symbol(0, isDay: false), "moon.stars.fill")
        XCTAssertEqual(WeatherCode.describe(1234), "Unknown")
    }
}
