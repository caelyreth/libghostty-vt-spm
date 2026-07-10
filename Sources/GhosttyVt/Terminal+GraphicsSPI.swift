import Foundation

extension Terminal {
    /// Serializes a graphics extension's short-lived inspection of the terminal.
    ///
    /// This is SPI for the companion `GhosttyVtGraphics` product. It keeps the
    /// C handle unavailable to ordinary `GhosttyVt` clients.
    @_spi(GhosttyVtGraphics)
    public func withTerminalHandle<Result>(
        _ body: (OpaquePointer) throws -> Result
    ) rethrows -> Result {
        try withTerminalLock {
            try body(handle)
        }
    }
}
