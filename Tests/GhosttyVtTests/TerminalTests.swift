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
