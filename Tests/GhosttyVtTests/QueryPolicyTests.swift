import XCTest
@testable import GhosttyVt

final class QueryPolicyTests: XCTestCase {
    func testEncodesFocusTransitions() throws {
        XCTAssertEqual(try Terminal.encodeFocus(.gained), Data("\u{1B}[I".utf8))
        XCTAssertEqual(try Terminal.encodeFocus(.lost), Data("\u{1B}[O".utf8))
    }

    func testQueryPolicyAnswersSizeAndColorSchemeQueries() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        try terminal.resize(to: .init(columns: 80, rows: 24), cellWidth: 8, cellHeight: 16)
        try terminal.setQueryPolicy(.init(size: .currentTerminal, colorScheme: .dark))

        terminal.feed("\u{1B}[18t\u{1B}[?996n")

        XCTAssertEqual(
            terminal.drainEvents(),
            [
                .writeToPty(Data("\u{1B}[8;24;80t".utf8)),
                .writeToPty(Data("\u{1B}[?997;1n".utf8)),
            ]
        )
    }

    func testQueryPolicyOwnsEnquiryAndXtermVersionResponses() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        try terminal.setQueryPolicy(.init(
            enquiryResponse: Data("answerback".utf8),
            xtermVersion: "RainBook 1.0"
        ))

        terminal.feed("\u{05}\u{1B}[>q")

        XCTAssertEqual(
            terminal.drainEvents(),
            [
                .writeToPty(Data("answerback".utf8)),
                .writeToPty(Data("\u{1B}P>|RainBook 1.0\u{1B}\\".utf8)),
            ]
        )
    }

    func testFocusReportingStatusFollowsTerminalMode() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        XCTAssertFalse(try terminal.isFocusReportingEnabled())

        terminal.feed("\u{1B}[?1004h")
        XCTAssertTrue(try terminal.isFocusReportingEnabled())
    }

    func testQueryPolicyRejectsInvalidValues() throws {
        let terminal = try Terminal(configuration: .init(columns: 4, rows: 2, maxScrollback: 0))

        XCTAssertThrowsError(
            try terminal.setQueryPolicy(.init(size: .fixed(.init(
                columns: 0,
                rows: 24,
                cellWidth: 8,
                cellHeight: 16
            ))))
        ) { error in
            XCTAssertEqual(error as? TerminalError, .invalidQuerySize)
        }
        XCTAssertThrowsError(
            try terminal.setQueryPolicy(.init(deviceAttributes: .init(
                primary: .init(conformanceLevel: 62, featureCodes: Array(repeating: 1, count: 65)),
                secondary: .init(deviceType: 1, firmwareVersion: 0)
            )))
        ) { error in
            XCTAssertEqual(error as? TerminalError, .invalidDeviceAttributes)
        }
        XCTAssertThrowsError(
            try terminal.setQueryPolicy(.init(xtermVersion: String(repeating: "a", count: 257)))
        ) { error in
            XCTAssertEqual(error as? TerminalError, .invalidXtermVersion)
        }
    }
}
