import Foundation
import GhosttyVtRaw

/// An owned, thread-safe libghostty-vt terminal.
///
/// `Terminal` serializes terminal access and separately serializes render-state
/// access. It is marked `@unchecked Sendable` because its C handles are
/// protected by those locks and never escape this type.
public final class Terminal: @unchecked Sendable {
    public struct Configuration: Sendable, Equatable {
        public var columns: UInt16
        public var rows: UInt16
        public var maxScrollback: Int

        public init(columns: UInt16 = 80, rows: UInt16 = 24, maxScrollback: Int = 10_000) {
            self.columns = columns
            self.rows = rows
            self.maxScrollback = maxScrollback
        }
    }

    public struct Size: Sendable, Equatable {
        public var columns: UInt16
        public var rows: UInt16

        public init(columns: UInt16, rows: UInt16) {
            self.columns = columns
            self.rows = rows
        }
    }

    // These members stay internal so the focused implementation extensions can
    // share them without exposing C types through the public API.
    let terminalLock = NSLock()
    let renderLock = NSLock()
    let handle: OpaquePointer
    let renderState: OpaquePointer
    var rowIterator: OpaquePointer?
    var rowCells: OpaquePointer?
    let keyEncoder: OpaquePointer
    let keyEvent: OpaquePointer
    let mouseEncoder: OpaquePointer
    let mouseEvent: OpaquePointer
    var cachedTheme: TerminalFrame.Theme?
    var graphemeBuffer: [UInt8] = []
    var graphemeCodepointBuffer: [UInt32] = []
    var inputBuffer = [UInt8](repeating: 0, count: 128)
    var pressedMouseButtons: UInt16 = 0
    var pendingEvents: [Event] = []
    var queryPolicy = QueryPolicy()
    var enquiryResponseStorage = TerminalQueryStringStorage()
    var xtermVersionStorage = TerminalQueryStringStorage()
    var currentSizeReport = QueryPolicy.Size(columns: 0, rows: 0, cellWidth: 0, cellHeight: 0)

    public init(configuration: Configuration = .init()) throws {
        guard configuration.columns > 0, configuration.rows > 0 else {
            throw TerminalError.invalidSize
        }
        guard configuration.maxScrollback >= 0 else {
            throw TerminalError.invalidScrollback
        }

        var options = GhosttyTerminalOptions()
        options.cols = configuration.columns
        options.rows = configuration.rows
        options.max_scrollback = configuration.maxScrollback

        var rawTerminal: OpaquePointer?
        try Self.check(ghostty_terminal_new(nil, &rawTerminal, options))
        guard let rawTerminal else {
            throw TerminalError.unexpectedResult
        }

        var rawRenderState: OpaquePointer?
        var rawRowIterator: OpaquePointer?
        var rawRowCells: OpaquePointer?
        var rawKeyEncoder: OpaquePointer?
        var rawKeyEvent: OpaquePointer?
        var rawMouseEncoder: OpaquePointer?
        var rawMouseEvent: OpaquePointer?
        do {
            try Self.check(ghostty_render_state_new(nil, &rawRenderState))
            try Self.check(ghostty_render_state_row_iterator_new(nil, &rawRowIterator))
            try Self.check(ghostty_render_state_row_cells_new(nil, &rawRowCells))
            try Self.check(ghostty_key_encoder_new(nil, &rawKeyEncoder))
            try Self.check(ghostty_key_event_new(nil, &rawKeyEvent))
            try Self.check(ghostty_mouse_encoder_new(nil, &rawMouseEncoder))
            try Self.check(ghostty_mouse_event_new(nil, &rawMouseEvent))
            guard
                let rawRenderState,
                let rawRowIterator,
                let rawRowCells,
                let rawKeyEncoder,
                let rawKeyEvent,
                let rawMouseEncoder,
                let rawMouseEvent
            else {
                throw TerminalError.unexpectedResult
            }

            handle = rawTerminal
            renderState = rawRenderState
            rowIterator = rawRowIterator
            rowCells = rawRowCells
            keyEncoder = rawKeyEncoder
            keyEvent = rawKeyEvent
            mouseEncoder = rawMouseEncoder
            mouseEvent = rawMouseEvent
            currentSizeReport = .init(
                columns: configuration.columns,
                rows: configuration.rows,
                cellWidth: 0,
                cellHeight: 0
            )
            try configureEffects()
        } catch {
            ghostty_mouse_event_free(rawMouseEvent)
            ghostty_mouse_encoder_free(rawMouseEncoder)
            ghostty_key_event_free(rawKeyEvent)
            ghostty_key_encoder_free(rawKeyEncoder)
            ghostty_render_state_row_cells_free(rawRowCells)
            ghostty_render_state_row_iterator_free(rawRowIterator)
            ghostty_render_state_free(rawRenderState)
            ghostty_terminal_free(rawTerminal)
            throw error
        }
    }

    deinit {
        ghostty_mouse_event_free(mouseEvent)
        ghostty_mouse_encoder_free(mouseEncoder)
        ghostty_key_event_free(keyEvent)
        ghostty_key_encoder_free(keyEncoder)
        ghostty_render_state_row_cells_free(rowCells)
        ghostty_render_state_row_iterator_free(rowIterator)
        ghostty_render_state_free(renderState)
        ghostty_terminal_free(handle)
    }

    /// Feeds raw terminal output into the VT parser without copying its bytes.
    public func feed(_ data: Data) {
        guard !data.isEmpty else { return }

        withTerminalLock {
            data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
                ghostty_terminal_vt_write(handle, baseAddress, bytes.count)
            }
        }
    }

    /// Feeds UTF-8 terminal output without constructing an intermediate `Data` value.
    public func feed(_ text: String) {
        guard !text.isEmpty else { return }

        var text = text
        text.withUTF8 { utf8 in
            withTerminalLock {
                guard let baseAddress = utf8.baseAddress else { return }
                ghostty_terminal_vt_write(handle, baseAddress, utf8.count)
            }
        }
    }

    /// Resizes the terminal grid and updates its reported pixel cell dimensions.
    public func resize(to size: Size, cellWidth: UInt32 = 0, cellHeight: UInt32 = 0) throws {
        guard size.columns > 0, size.rows > 0 else {
            throw TerminalError.invalidSize
        }

        try withTerminalLock {
            try Self.check(
                ghostty_terminal_resize(handle, size.columns, size.rows, cellWidth, cellHeight)
            )
            currentSizeReport = .init(
                columns: size.columns,
                rows: size.rows,
                cellWidth: cellWidth,
                cellHeight: cellHeight
            )
        }
    }

    /// Resets the terminal state while preserving its dimensions.
    public func reset() {
        withTerminalLock {
            ghostty_terminal_reset(handle)
        }
    }

    func withTerminalLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        terminalLock.lock()
        defer { terminalLock.unlock() }
        return try body()
    }
}

public enum TerminalError: Error, Sendable, Equatable {
    case invalidSize
    case invalidScrollback
    case invalidValue
    case outOfMemory
    case outOfSpace
    case noValue
    case invalidKey
    case invalidMouseButton
    case invalidMouseGeometry
    case invalidPalette
    case invalidViewportRow
    case invalidQuerySize
    case invalidDeviceAttributes
    case invalidXtermVersion
    case invalidRenderTransaction
    case invalidSelectionGestureConfiguration
    case invalidSelectionGestureGeometry
    case unexpectedResult
}
