import GhosttyVtRaw

extension Terminal {
    private static let frameDataKeys: [GhosttyRenderStateData] = [
        GHOSTTY_RENDER_STATE_DATA_COLS,
        GHOSTTY_RENDER_STATE_DATA_ROWS,
        GHOSTTY_RENDER_STATE_DATA_DIRTY,
    ]

    private static let cursorDataKeys: [GhosttyRenderStateData] = [
        GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE,
        GHOSTTY_RENDER_STATE_DATA_CURSOR_BLINKING,
        GHOSTTY_RENDER_STATE_DATA_CURSOR_PASSWORD_INPUT,
        GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE,
        GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE,
    ]

    private static let cursorPositionDataKeys: [GhosttyRenderStateData] = [
        GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X,
        GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y,
        GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL,
    ]

    /// Captures a Swift-owned incremental render update.
    ///
    /// This uses libghostty-vt's two-phase render update. Terminal access is
    /// locked only for the first phase; copying the render state then proceeds
    /// without blocking terminal input.
    public func update() throws -> TerminalFrame {
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
        let rows = try changedRows(for: metadata.dirtyState, size: metadata.size)

        try clearGlobalDirtyState()

        return .init(
            size: metadata.size,
            dirtyState: metadata.dirtyState,
            theme: theme,
            cursor: cursor,
            rows: rows
        )
    }

    private func frameMetadata() throws -> (size: Size, dirtyState: TerminalFrame.DirtyState) {
        var columns: UInt16 = 0
        var rows: UInt16 = 0
        var rawDirtyState: GhosttyRenderStateDirty = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        var written = 0

        let result = COutputPointers.withPointers(&columns, &rows, &rawDirtyState) { values in
            Self.frameDataKeys.withUnsafeBufferPointer { keyBuffer in
                ghostty_render_state_get_multi(
                    renderState,
                    keyBuffer.count,
                    keyBuffer.baseAddress,
                    values.baseAddress,
                    &written
                )
            }
        }
        try Self.check(result)
        guard written == Self.frameDataKeys.count else {
            throw TerminalError.unexpectedResult
        }

        let dirtyState: TerminalFrame.DirtyState
        switch rawDirtyState {
        case GHOSTTY_RENDER_STATE_DIRTY_PARTIAL:
            dirtyState = .partial
        case GHOSTTY_RENDER_STATE_DIRTY_FULL:
            dirtyState = .full
        default:
            dirtyState = .clean
        }

        return (.init(columns: columns, rows: rows), dirtyState)
    }

    private func frameTheme(refresh: Bool) throws -> TerminalFrame.Theme {
        if !refresh, let cachedTheme {
            return cachedTheme
        }

        var colors = GhosttyRenderStateColors()
        colors.size = MemoryLayout<GhosttyRenderStateColors>.size
        try Self.check(ghostty_render_state_colors_get(renderState, &colors))

        let palette = withUnsafeBytes(of: &colors.palette) { bytes in
            bytes.bindMemory(to: GhosttyColorRgb.self).map(Self.color(from:))
        }

        let theme = TerminalFrame.Theme(
            foreground: Self.color(from: colors.foreground),
            background: Self.color(from: colors.background),
            cursor: colors.cursor_has_value ? Self.color(from: colors.cursor) : nil,
            palette: palette
        )
        cachedTheme = theme
        return theme
    }

    private func frameCursor() throws -> TerminalFrame.Cursor {
        var visible = false
        var blinking = false
        var passwordInput = false
        var hasPosition = false
        var style: GhosttyRenderStateCursorVisualStyle = GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK

        var written = 0
        let result = COutputPointers.withPointers(
            &visible,
            &blinking,
            &passwordInput,
            &hasPosition,
            &style
        ) { values in
            Self.cursorDataKeys.withUnsafeBufferPointer { keyBuffer in
                ghostty_render_state_get_multi(
                    renderState,
                    keyBuffer.count,
                    keyBuffer.baseAddress,
                    values.baseAddress,
                    &written
                )
            }
        }
        try Self.check(result)
        guard written == Self.cursorDataKeys.count else {
            throw TerminalError.unexpectedResult
        }

        guard hasPosition else {
            return .init(
                isVisible: visible,
                isBlinking: blinking,
                isPasswordInput: passwordInput,
                isWideTail: false,
                style: Self.cursorStyle(from: style),
                position: nil
            )
        }

        var column: UInt16 = 0
        var row: UInt16 = 0
        var isWideTail = false
        written = 0
        let positionResult = COutputPointers.withPointers(&column, &row, &isWideTail) { values in
            Self.cursorPositionDataKeys.withUnsafeBufferPointer { keyBuffer in
                ghostty_render_state_get_multi(
                    renderState,
                    keyBuffer.count,
                    keyBuffer.baseAddress,
                    values.baseAddress,
                    &written
                )
            }
        }
        try Self.check(positionResult)
        guard written == Self.cursorPositionDataKeys.count else {
            throw TerminalError.unexpectedResult
        }

        return .init(
            isVisible: visible,
            isBlinking: blinking,
            isPasswordInput: passwordInput,
            isWideTail: isWideTail,
            style: Self.cursorStyle(from: style),
            position: .init(column: column, row: row)
        )
    }

    private func changedRows(
        for dirtyState: TerminalFrame.DirtyState,
        size: Size
    ) throws -> [TerminalFrame.Row] {
        guard dirtyState != .clean else { return [] }

        try Self.check(
            ghostty_render_state_get(
                renderState,
                GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                &rowIterator
            )
        )
        guard let rowIterator else {
            throw TerminalError.unexpectedResult
        }

        var rows: [TerminalFrame.Row] = []
        if dirtyState == .full {
            rows.reserveCapacity(Int(size.rows))
        }
        var rowIndex: UInt16 = 0
        while ghostty_render_state_row_iterator_next(rowIterator) {
            var isDirty = false
            try Self.check(
                ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &isDirty)
            )

            guard dirtyState == .full || isDirty else {
                rowIndex &+= 1
                continue
            }

            var rawRow: UInt64 = 0
            try Self.check(
                ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_RAW, &rawRow)
            )
            try Self.check(
                ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &rowCells)
            )
            guard let rowCells else {
                throw TerminalError.unexpectedResult
            }

            let metadata = try rowMetadata(rawRow)
            let selection = try rowSelection(rowIterator)
            let renderedCells = try cells(in: rowCells, columnCount: size.columns)
            rows.append(
                .init(
                    index: rowIndex,
                    isSoftWrapped: metadata.isSoftWrapped,
                    isContinuation: metadata.isContinuation,
                    semanticPrompt: metadata.semanticPrompt,
                    selection: selection,
                    cells: renderedCells
                )
            )

            var clean = false
            try Self.check(
                ghostty_render_state_row_set(rowIterator, GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY, &clean)
            )
            rowIndex &+= 1
        }

        return rows
    }

    private func rowMetadata(_ rawRow: UInt64) throws -> (
        isSoftWrapped: Bool,
        isContinuation: Bool,
        semanticPrompt: TerminalFrame.SemanticPrompt
    ) {
        var isSoftWrapped = false
        var isContinuation = false
        var semanticPrompt: GhosttyRowSemanticPrompt = GHOSTTY_ROW_SEMANTIC_NONE
        try Self.check(ghostty_row_get(rawRow, GHOSTTY_ROW_DATA_WRAP, &isSoftWrapped))
        try Self.check(ghostty_row_get(rawRow, GHOSTTY_ROW_DATA_WRAP_CONTINUATION, &isContinuation))
        try Self.check(ghostty_row_get(rawRow, GHOSTTY_ROW_DATA_SEMANTIC_PROMPT, &semanticPrompt))

        return (
            isSoftWrapped,
            isContinuation,
            Self.semanticPrompt(from: semanticPrompt)
        )
    }

    private func rowSelection(_ iterator: OpaquePointer) throws -> TerminalFrame.Selection? {
        var rawSelection = GhosttyRenderStateRowSelection()
        rawSelection.size = MemoryLayout<GhosttyRenderStateRowSelection>.size
        let result = ghostty_render_state_row_get(
            iterator,
            GHOSTTY_RENDER_STATE_ROW_DATA_SELECTION,
            &rawSelection
        )

        if result == GHOSTTY_NO_VALUE {
            return nil
        }
        try Self.check(result)
        return .init(startColumn: rawSelection.start_x, endColumn: rawSelection.end_x)
    }

    private func clearGlobalDirtyState() throws {
        var clean: GhosttyRenderStateDirty = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        try Self.check(
            ghostty_render_state_set(renderState, GHOSTTY_RENDER_STATE_OPTION_DIRTY, &clean)
        )
    }
}
