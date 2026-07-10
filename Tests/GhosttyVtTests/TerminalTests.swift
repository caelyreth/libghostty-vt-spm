import Dispatch
import XCTest
@testable import GhosttyVt

final class TerminalTests: XCTestCase {
    func testUpdateReturnsSwiftOwnedRichCells() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        _ = try terminal.update()

        terminal.feed("\u{1B}[1;31mA\u{1B}[0m")
        let frame = try terminal.update()
        let cell = try XCTUnwrap(cell(withText: "A", in: frame))

        XCTAssertNotEqual(frame.dirtyState, .clean)
        XCTAssertEqual(frame.theme.palette.count, 256)
        XCTAssertTrue(cell.style.isBold)
        XCTAssertEqual(cell.style.foreground, .palette(1))
        XCTAssertNotNil(cell.resolvedForeground)
        XCTAssertEqual(cell.width, .narrow)
        XCTAssertEqual(cell.semanticContent, .output)
    }

    func testUpdateConsumesBothDirtyLayers() throws {
        let terminal = try Terminal(configuration: .init(columns: 4, rows: 2, maxScrollback: 0))
        _ = try terminal.update()

        terminal.feed("A")
        let changed = try terminal.update()
        XCTAssertNotEqual(changed.dirtyState, .clean)
        XCTAssertFalse(changed.rows.isEmpty)

        let clean = try terminal.update()
        XCTAssertEqual(clean.dirtyState, .clean)
        XCTAssertTrue(clean.rows.isEmpty)
    }

    func testRenderTransactionBorrowsDirtyCellsWithoutBuildingAFrame() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        _ = try terminal.update()
        terminal.feed("A\u{754C}")

        var rendered: [(UInt16, String)] = []
        try terminal.withRenderTransaction { transaction in
            XCTAssertEqual(transaction.dirtyState, .partial)
            try transaction.forEachRow { row in
                try row.forEachCell { cell in
                    let text = try cell.withUTF8 { String(decoding: $0, as: UTF8.self) }
                    if !text.isEmpty {
                        rendered.append((cell.column, text))
                    }
                }
            }
        }

        XCTAssertEqual(rendered.map { $0.1 }, ["A", "\u{754C}"])
        XCTAssertEqual(rendered.map { $0.0 }, [0, 1])
        XCTAssertEqual(try terminal.update().dirtyState, .clean)
    }

    func testUpdateResolvesTrueColorBackgrounds() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        _ = try terminal.update()

        terminal.feed("\u{1B}[48;2;1;2;3mB\u{1B}[0m")
        let frame = try terminal.update()
        let cell = try XCTUnwrap(cell(withText: "B", in: frame))

        XCTAssertEqual(cell.style.background, .rgb(.init(red: 1, green: 2, blue: 3)))
        XCTAssertEqual(cell.resolvedBackground, .init(red: 1, green: 2, blue: 3))
    }

    func testUpdatePreservesUnicodeGraphemesAndWideCells() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        _ = try terminal.update()

        terminal.feed("\u{754C}e\u{301}")
        let frame = try terminal.update()

        let wide = try XCTUnwrap(cell(withText: "\u{754C}", in: frame))
        XCTAssertEqual(wide.width, .wide)
        XCTAssertNotNil(cell(withText: "e\u{301}", in: frame))
    }

    func testResizeProducesAFullFrame() throws {
        let terminal = try Terminal(configuration: .init(columns: 4, rows: 2, maxScrollback: 0))
        _ = try terminal.update()

        try terminal.resize(to: .init(columns: 6, rows: 3), cellWidth: 8, cellHeight: 16)
        let frame = try terminal.update()

        XCTAssertEqual(frame.size, .init(columns: 6, rows: 3))
        XCTAssertEqual(frame.dirtyState, .full)
        XCTAssertEqual(frame.rows.count, 3)
    }

    func testEncodesTerminalInput() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))

        XCTAssertEqual(try terminal.encode(.init(text: "a")), Data("a".utf8))
        XCTAssertEqual(try terminal.encode(.init(key: .enter)), Data([0x0D]))
        XCTAssertTrue(Terminal.isPasteSafe("safe"))
        XCTAssertFalse(Terminal.isPasteSafe("first\nsecond"))
        XCTAssertEqual(try terminal.encodePaste("first\nsecond"), Data("first\rsecond".utf8))
    }

    func testMouseEncodingUsesTerminalReportingMode() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        terminal.feed("\u{1B}[?1000h\u{1B}[?1006h")

        let output = try terminal.encode(
            .init(
                action: .press,
                button: .left,
                position: .init(x: 12, y: 12)
            ),
            geometry: .init(screenWidth: 80, screenHeight: 32, cellWidth: 8, cellHeight: 16)
        )

        XCTAssertEqual(output, Data("\u{1B}[<0;2;1M".utf8))
    }

    func testDrainEventsReturnsCopiedTerminalEffects() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        terminal.feed("\u{07}\u{1B}]2;RainBook\u{07}\u{1B}]7;file:///tmp\u{07}\u{1B}[5n")

        XCTAssertEqual(
            terminal.drainEvents(),
            [
                .bell,
                .titleChanged("RainBook"),
                .workingDirectoryChanged("file:///tmp"),
                .writeToPty(Data("\u{1B}[0n".utf8)),
            ]
        )
        XCTAssertTrue(terminal.drainEvents().isEmpty)
    }

    func testControlsExposeTerminalStatusAndTheme() throws {
        let terminal = try Terminal(configuration: .init(columns: 4, rows: 2, maxScrollback: 4))
        let palette = [TerminalFrame.RGBColor](repeating: .init(red: 4, green: 5, blue: 6), count: 256)
        try terminal.setDefaultTheme(
            .init(
                foreground: .init(red: 1, green: 2, blue: 3),
                background: .init(red: 7, green: 8, blue: 9),
                cursor: .init(red: 10, green: 11, blue: 12),
                palette: palette
            )
        )
        terminal.feed("one\\r\\ntwo\\r\\nthree")
        try terminal.scroll(to: .top)

        let status = try terminal.status()
        let frame = try terminal.update()

        XCTAssertEqual(status.activeScreen, .primary)
        XCTAssertGreaterThan(status.scrollbackRows, 0)
        XCTAssertFalse(status.isViewportActive)
        XCTAssertEqual(frame.theme.foreground, .init(red: 1, green: 2, blue: 3))
        XCTAssertEqual(frame.theme.background, .init(red: 7, green: 8, blue: 9))
        XCTAssertEqual(frame.theme.cursor, .init(red: 10, green: 11, blue: 12))
        XCTAssertEqual(frame.theme.palette.first, .init(red: 4, green: 5, blue: 6))
    }

    func testControlsRejectInvalidValues() throws {
        let terminal = try Terminal(configuration: .init(columns: 4, rows: 2, maxScrollback: 0))

        XCTAssertThrowsError(try terminal.scroll(to: .row(-1))) { error in
            XCTAssertEqual(error as? TerminalError, .invalidViewportRow)
        }
        XCTAssertThrowsError(
            try terminal.setDefaultTheme(.init(palette: [.init(red: 1, green: 2, blue: 3)]))
        ) { error in
            XCTAssertEqual(error as? TerminalError, .invalidPalette)
        }
    }

    func testSelectionUsesViewportCellsAndFormatsClipboardText() throws {
        let terminal = try Terminal(configuration: .init(columns: 16, rows: 3, maxScrollback: 0))
        terminal.feed("alpha beta\r\nsecond line")

        try terminal.select(
            from: .init(column: 0, row: 0),
            to: .init(column: 4, row: 0)
        )
        XCTAssertEqual(try terminal.copySelection(), "alpha")

        try terminal.selectWord(at: .init(column: 7, row: 0))
        XCTAssertEqual(try terminal.copySelection(), "beta")

        try terminal.selectLine(at: .init(column: 2, row: 1))
        XCTAssertEqual(try terminal.copySelection(), "second line")

        try terminal.selectAll()
        XCTAssertEqual(try terminal.copySelection(), "alpha beta\nsecond line")

        try terminal.clearSelection()
        XCTAssertThrowsError(try terminal.copySelection()) { error in
            XCTAssertEqual(error as? TerminalError, .noValue)
        }
    }

    func testTerminalIsSendableAndSynchronizesConcurrentAccess() throws {
        assertSendable(Terminal.self)

        let terminal = try Terminal(configuration: .init(columns: 16, rows: 4, maxScrollback: 0))
        let queue = DispatchQueue(label: "GhosttyVtTests.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        for index in 0 ..< 32 {
            group.enter()
            queue.async {
                if index.isMultiple(of: 2) {
                    terminal.feed("\(index)")
                } else {
                    _ = try? terminal.update()
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        _ = try terminal.update()
    }

    func testInvalidDimensionsAreRejectedBeforeCreatingATerminal() {
        XCTAssertThrowsError(
            try Terminal(configuration: .init(columns: 0, rows: 24, maxScrollback: 0))
        ) { error in
            XCTAssertEqual(error as? TerminalError, .invalidSize)
        }
    }

    private func cell(withText text: String, in frame: TerminalFrame) -> TerminalFrame.Cell? {
        frame.rows.lazy.flatMap(\.cells).first { $0.text == text }
    }

    private func assertSendable<Value: Sendable>(_ type: Value.Type) {}
}
