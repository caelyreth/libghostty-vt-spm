import XCTest
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
}
