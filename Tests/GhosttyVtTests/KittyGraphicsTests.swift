import XCTest
@testable import GhosttyVt
@testable import GhosttyVtGraphics

final class KittyGraphicsTests: XCTestCase {
    func testPNGImageValidatesRGBAByteCount() throws {
        let image = try KittyGraphics.PNGImage(
            width: 2,
            height: 1,
            pixels: Data(repeating: 0, count: 8)
        )
        XCTAssertEqual(image.pixels.count, 8)

        XCTAssertThrowsError(
            try KittyGraphics.PNGImage(width: 2, height: 1, pixels: Data(repeating: 0, count: 7))
        ) { error in
            XCTAssertEqual(error as? KittyGraphics.Error, .invalidPNGImage)
        }
    }

    func testGraphicsConfigurationDefaultsToSafeMediaPolicy() {
        let configuration = KittyGraphicsConfiguration()
        XCTAssertEqual(configuration.storageLimitBytes, 64 * 1024 * 1024)
        XCTAssertFalse(configuration.allowsFileMedium)
        XCTAssertFalse(configuration.allowsTemporaryFileMedium)
        XCTAssertFalse(configuration.allowsSharedMemoryMedium)
    }

    func testPlacementKeepsOnlyCopiedGridBounds() {
        let bounds = Terminal.GridRange(
            start: .init(column: 1, row: 2, coordinateSpace: .screen),
            end: .init(column: 3, row: 4, coordinateSpace: .screen),
            isRectangular: true
        )
        let placement = KittyGraphicsPlacement(
            imageIdentifier: 1,
            placementIdentifier: 2,
            isVirtual: false,
            xOffset: 0,
            yOffset: 0,
            zIndex: 0,
            renderInfo: .init(
                pixelWidth: 8,
                pixelHeight: 16,
                gridColumns: 1,
                gridRows: 1,
                viewportColumn: 1,
                viewportRow: 2,
                isViewportVisible: true,
                sourceX: 0,
                sourceY: 0,
                sourceWidth: 8,
                sourceHeight: 16
            ),
            gridBounds: bounds
        )
        XCTAssertEqual(placement.gridBounds, bounds)
    }
}
