import XCTest
@testable import GhosttyVt

final class SelectionGestureTests: XCTestCase {
    func testGestureInstallsDragSelectionAndReportsState() throws {
        let terminal = try Terminal(configuration: .init(columns: 12, rows: 2, maxScrollback: 0))
        terminal.feed("hello world")
        let gesture = try terminal.makeSelectionGesture()

        let pressed = try gesture.press(
            at: .init(column: 0, row: 0),
            position: .init(x: 2, y: 8),
            timestampNanoseconds: 1
        )
        XCTAssertFalse(pressed.selectionChanged)
        XCTAssertEqual(pressed.behavior, .cell)

        let dragged = try gesture.drag(
            to: .init(column: 4, row: 0),
            position: .init(x: 42, y: 8),
            geometry: .init(columns: 12, cellWidth: 8, screenHeight: 32)
        )
        XCTAssertTrue(dragged.selectionChanged)
        XCTAssertTrue(dragged.hasDragged)
        XCTAssertEqual(try terminal.copySelection(), "hello")

        let released = try gesture.release(at: .init(column: 4, row: 0))
        XCTAssertFalse(released.selectionChanged)
        XCTAssertTrue(released.hasDragged)
    }

    func testGestureRejectsInvalidGeometry() throws {
        let terminal = try Terminal(configuration: .init(columns: 8, rows: 2, maxScrollback: 0))
        let gesture = try terminal.makeSelectionGesture()
        _ = try gesture.press(at: .init(column: 0, row: 0), position: .init(x: 0, y: 0))

        XCTAssertThrowsError(
            try gesture.drag(
                to: .init(column: 1, row: 0),
                position: .init(x: 8, y: 0),
                geometry: .init(columns: 0, cellWidth: 8, screenHeight: 32)
            )
        ) { error in
            XCTAssertEqual(error as? TerminalError, .invalidSelectionGestureGeometry)
        }
    }
}
