import Foundation
import GhosttyVtRaw

extension Terminal {
    /// Runs a synchronous, allocation-conscious render pass over the current terminal state.
    ///
    /// The transaction, rows, cells, and buffers passed to its closures are valid only while
    /// this method is executing. They must not escape the closure or cross concurrency domains.
    /// Use `update()` when a Swift-owned, `Sendable` frame is required.
    public func withRenderTransaction<Result>(
        _ body: (RenderTransaction) throws -> Result
    ) throws -> Result {
        renderLock.lock()
        defer { renderLock.unlock() }

        let beginResult = withTerminalLock {
            ghostty_render_state_begin_update(renderState, handle)
        }
        try Self.check(beginResult)
        try Self.check(ghostty_render_state_end_update(renderState))

        let metadata = try frameMetadata()
        let theme = try frameTheme(refresh: metadata.dirtyState == .full || cachedTheme == nil)
        let cursor = try frameCursor()
        let state = RenderTransactionState(terminal: self)
        let transaction = RenderTransaction(
            state: state,
            size: metadata.size,
            dirtyState: metadata.dirtyState,
            theme: theme,
            cursor: cursor
        )

        defer {
            state.isActive = false
            try? clearGlobalDirtyState()
        }
        return try body(transaction)
    }
}

/// A scoped view of a libghostty-vt render update.
///
/// Instances are provided only by `Terminal.withRenderTransaction(_:)`.
public struct RenderTransaction {
    fileprivate let state: RenderTransactionState
    public let size: Terminal.Size
    public let dirtyState: TerminalFrame.DirtyState
    public let theme: TerminalFrame.Theme
    public let cursor: TerminalFrame.Cursor

    fileprivate init(
        state: RenderTransactionState,
        size: Terminal.Size,
        dirtyState: TerminalFrame.DirtyState,
        theme: TerminalFrame.Theme,
        cursor: TerminalFrame.Cursor
    ) {
        self.state = state
        self.size = size
        self.dirtyState = dirtyState
        self.theme = theme
        self.cursor = cursor
    }

    /// Visits each dirty row, or every row after a full invalidation.
    public func forEachRow(_ body: (RenderRow) throws -> Void) throws {
        try state.checkActive()
        guard dirtyState != .clean else { return }

        let terminal = state.terminal
        try Terminal.check(
            ghostty_render_state_get(
                terminal.renderState,
                GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                &terminal.rowIterator
            )
        )
        guard let iterator = terminal.rowIterator else {
            throw TerminalError.unexpectedResult
        }

        var index: UInt16 = 0
        while ghostty_render_state_row_iterator_next(iterator) {
            var isDirty = false
            try Terminal.check(
                ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &isDirty)
            )
            defer { index &+= 1 }
            guard dirtyState == .full || isDirty else { continue }

            var rawRow: UInt64 = 0
            try Terminal.check(
                ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_RAW, &rawRow)
            )
            try Terminal.check(
                ghostty_render_state_row_get(
                    iterator,
                    GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
                    &terminal.rowCells
                )
            )
            guard let cells = terminal.rowCells else {
                throw TerminalError.unexpectedResult
            }

            let metadata = try terminal.rowMetadata(rawRow)
            let rowState = RenderRowState(transaction: state)
            let row = RenderRow(
                state: rowState,
                index: index,
                isSoftWrapped: metadata.isSoftWrapped,
                isContinuation: metadata.isContinuation,
                semanticPrompt: metadata.semanticPrompt,
                selection: try terminal.rowSelection(iterator),
                cells: cells
            )
            defer {
                rowState.isActive = false
                var clean = false
                _ = ghostty_render_state_row_set(
                    iterator,
                    GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY,
                    &clean
                )
            }
            try body(row)
        }
    }
}

/// A scoped render row. It is valid only for the duration of its row callback.
public struct RenderRow {
    fileprivate let state: RenderRowState
    fileprivate let cells: OpaquePointer
    public let index: UInt16
    public let isSoftWrapped: Bool
    public let isContinuation: Bool
    public let semanticPrompt: TerminalFrame.SemanticPrompt
    public let selection: TerminalFrame.Selection?

    fileprivate init(
        state: RenderRowState,
        index: UInt16,
        isSoftWrapped: Bool,
        isContinuation: Bool,
        semanticPrompt: TerminalFrame.SemanticPrompt,
        selection: TerminalFrame.Selection?,
        cells: OpaquePointer
    ) {
        self.state = state
        self.index = index
        self.isSoftWrapped = isSoftWrapped
        self.isContinuation = isContinuation
        self.semanticPrompt = semanticPrompt
        self.selection = selection
        self.cells = cells
    }

    /// Visits cells in column order without constructing a `TerminalFrame.Row`.
    public func forEachCell(_ body: (RenderCell) throws -> Void) throws {
        try state.checkActive()

        var column: UInt16 = 0
        while ghostty_render_state_row_cells_next(cells) {
            let cell = try RenderCell(state: state, column: column, cells: cells)
            try body(cell)
            column &+= 1
        }
    }
}

/// A scoped render cell. Its grapheme buffers are borrowed for callback duration only.
public struct RenderCell {
    fileprivate let state: RenderRowState
    fileprivate let cells: OpaquePointer
    public let column: UInt16
    public let graphemeCount: UInt32
    public let width: TerminalFrame.CellWidth
    public let style: TerminalFrame.Style
    public let resolvedForeground: TerminalFrame.RGBColor?
    public let resolvedBackground: TerminalFrame.RGBColor?
    public let hasHyperlink: Bool
    public let isProtected: Bool
    public let semanticContent: TerminalFrame.SemanticContent

    fileprivate init(state: RenderRowState, column: UInt16, cells: OpaquePointer) throws {
        try state.checkActive()

        var rawCell: UInt64 = 0
        var rawStyle = GhosttyStyle()
        rawStyle.size = MemoryLayout<GhosttyStyle>.size
        var graphemeCount: UInt32 = 0
        var written = 0
        let rowCellResult = COutputPointers.withPointers(
            &rawCell,
            &rawStyle,
            &graphemeCount
        ) { values in
            RenderTransactionData.rowCellDataKeys.withUnsafeBufferPointer { keys in
                ghostty_render_state_row_cells_get_multi(
                    cells,
                    keys.count,
                    keys.baseAddress,
                    values.baseAddress,
                    &written
                )
            }
        }
        try Terminal.check(rowCellResult)
        guard written == RenderTransactionData.rowCellDataKeys.count else {
            throw TerminalError.unexpectedResult
        }

        var rawContent: GhosttyCellContentTag = GHOSTTY_CELL_CONTENT_CODEPOINT
        var rawWidth: GhosttyCellWide = GHOSTTY_CELL_WIDE_NARROW
        var hasHyperlink = false
        var isProtected = false
        var rawSemanticContent: GhosttyCellSemanticContent = GHOSTTY_CELL_SEMANTIC_OUTPUT
        written = 0
        let metadataResult = COutputPointers.withPointers(
            &rawContent,
            &rawWidth,
            &hasHyperlink,
            &isProtected,
            &rawSemanticContent
        ) { values in
            RenderTransactionData.cellDataKeys.withUnsafeBufferPointer { keys in
                ghostty_cell_get_multi(rawCell, keys.count, keys.baseAddress, values.baseAddress, &written)
            }
        }
        try Terminal.check(metadataResult)
        guard written == RenderTransactionData.cellDataKeys.count else {
            throw TerminalError.unexpectedResult
        }

        self.state = state
        self.cells = cells
        self.column = column
        self.graphemeCount = graphemeCount
        self.width = Terminal.cellWidth(from: rawWidth)
        self.style = Terminal.style(from: rawStyle)
        self.resolvedForeground = try Self.resolvedColor(
            in: cells,
            data: GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR,
            isNeeded: rawStyle.fg_color.tag != GHOSTTY_STYLE_COLOR_NONE
        )
        self.resolvedBackground = try Self.resolvedColor(
            in: cells,
            data: GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR,
            isNeeded: rawStyle.bg_color.tag != GHOSTTY_STYLE_COLOR_NONE ||
                rawContent == GHOSTTY_CELL_CONTENT_BG_COLOR_PALETTE ||
                rawContent == GHOSTTY_CELL_CONTENT_BG_COLOR_RGB
        )
        self.hasHyperlink = hasHyperlink
        self.isProtected = isProtected
        self.semanticContent = Terminal.semanticContent(from: rawSemanticContent)
    }

    /// Borrows Unicode scalar values for the current cell's grapheme cluster.
    public func withCodepoints<Result>(
        _ body: (UnsafeBufferPointer<UInt32>) throws -> Result
    ) throws -> Result {
        try state.checkActive()
        guard graphemeCount > 0 else {
            return try body(.init(start: nil, count: 0))
        }

        let terminal = state.transaction.terminal
        let capacity = Int(graphemeCount)
        if terminal.graphemeCodepointBuffer.count < capacity {
            terminal.graphemeCodepointBuffer = [UInt32](repeating: 0, count: capacity)
        }
        return try terminal.graphemeCodepointBuffer.withUnsafeMutableBufferPointer { buffer in
            try Terminal.check(
                ghostty_render_state_row_cells_get(
                    cells,
                    GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                    buffer.baseAddress
                )
            )
            return try body(.init(start: buffer.baseAddress, count: capacity))
        }
    }

    /// Borrows UTF-8 bytes for the current cell's grapheme cluster.
    public func withUTF8<Result>(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
    ) throws -> Result {
        try state.checkActive()
        guard graphemeCount > 0 else {
            return try body(.init(start: nil, count: 0))
        }

        let terminal = state.transaction.terminal
        let capacity = Int(graphemeCount) * 4
        if terminal.graphemeBuffer.count < capacity {
            terminal.graphemeBuffer = [UInt8](repeating: 0, count: capacity)
        }
        return try terminal.graphemeBuffer.withUnsafeMutableBufferPointer { bytes in
            var buffer = GhosttyBuffer()
            buffer.ptr = bytes.baseAddress
            buffer.cap = bytes.count
            buffer.len = 0
            try Terminal.check(
                ghostty_render_state_row_cells_get(
                    cells,
                    GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8,
                    &buffer
                )
            )
            guard buffer.len <= bytes.count else {
                throw TerminalError.unexpectedResult
            }
            return try body(.init(start: bytes.baseAddress, count: buffer.len))
        }
    }

    private static func resolvedColor(
        in cells: OpaquePointer,
        data: GhosttyRenderStateRowCellsData,
        isNeeded: Bool
    ) throws -> TerminalFrame.RGBColor? {
        guard isNeeded else { return nil }

        var rawColor = GhosttyColorRgb()
        let result = ghostty_render_state_row_cells_get(cells, data, &rawColor)
        if result == GHOSTTY_SUCCESS {
            return Terminal.color(from: rawColor)
        }
        if result == GHOSTTY_INVALID_VALUE {
            return nil
        }
        try Terminal.check(result)
        return nil
    }
}

fileprivate final class RenderTransactionState {
    let terminal: Terminal
    var isActive = true

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    func checkActive() throws {
        guard isActive else { throw TerminalError.invalidRenderTransaction }
    }
}

fileprivate final class RenderRowState {
    let transaction: RenderTransactionState
    var isActive = true

    init(transaction: RenderTransactionState) {
        self.transaction = transaction
    }

    func checkActive() throws {
        try transaction.checkActive()
        guard isActive else { throw TerminalError.invalidRenderTransaction }
    }
}

private enum RenderTransactionData {
    static let rowCellDataKeys: [GhosttyRenderStateRowCellsData] = [
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW,
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE,
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
    ]

    static let cellDataKeys: [GhosttyCellData] = [
        GHOSTTY_CELL_DATA_CONTENT_TAG,
        GHOSTTY_CELL_DATA_WIDE,
        GHOSTTY_CELL_DATA_HAS_HYPERLINK,
        GHOSTTY_CELL_DATA_PROTECTED,
        GHOSTTY_CELL_DATA_SEMANTIC_CONTENT,
    ]
}
