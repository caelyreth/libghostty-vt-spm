import GhosttyVtRaw

extension Terminal {
    private static let rowCellDataKeys: [GhosttyRenderStateRowCellsData] = [
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW,
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE,
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
    ]

    private static let cellDataKeys: [GhosttyCellData] = [
        GHOSTTY_CELL_DATA_CONTENT_TAG,
        GHOSTTY_CELL_DATA_WIDE,
        GHOSTTY_CELL_DATA_HAS_HYPERLINK,
        GHOSTTY_CELL_DATA_PROTECTED,
        GHOSTTY_CELL_DATA_SEMANTIC_CONTENT,
    ]

    func cells(
        in rowCells: OpaquePointer,
        columnCount: UInt16
    ) throws -> [TerminalFrame.Cell] {
        var cells: [TerminalFrame.Cell] = []
        cells.reserveCapacity(Int(columnCount))
        var column: UInt16 = 0
        while ghostty_render_state_row_cells_next(rowCells) {
            cells.append(try cell(at: column, in: rowCells))
            column &+= 1
        }
        return cells
    }

    private func cell(at column: UInt16, in rowCells: OpaquePointer) throws -> TerminalFrame.Cell {
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
            Self.rowCellDataKeys.withUnsafeBufferPointer { keyBuffer in
                ghostty_render_state_row_cells_get_multi(
                    rowCells,
                    keyBuffer.count,
                    keyBuffer.baseAddress,
                    values.baseAddress,
                    &written
                )
            }
        }
        try Self.check(rowCellResult)
        guard written == Self.rowCellDataKeys.count else {
            throw TerminalError.unexpectedResult
        }

        let metadata = try cellMetadata(rawCell)
        let style = Self.style(from: rawStyle)
        let colors = try resolvedColors(
            in: rowCells,
            style: style,
            hasExplicitBackground: metadata.hasExplicitBackground
        )
        return .init(
            column: column,
            text: try cellText(in: rowCells, graphemeCount: graphemeCount),
            width: metadata.width,
            style: style,
            resolvedForeground: colors.foreground,
            resolvedBackground: colors.background,
            hasHyperlink: metadata.hasHyperlink,
            isProtected: metadata.isProtected,
            semanticContent: metadata.semanticContent
        )
    }

    private func cellMetadata(_ rawCell: UInt64) throws -> (
        width: TerminalFrame.CellWidth,
        hasExplicitBackground: Bool,
        hasHyperlink: Bool,
        isProtected: Bool,
        semanticContent: TerminalFrame.SemanticContent
    ) {
        var rawContent: GhosttyCellContentTag = GHOSTTY_CELL_CONTENT_CODEPOINT
        var rawWidth: GhosttyCellWide = GHOSTTY_CELL_WIDE_NARROW
        var hasHyperlink = false
        var isProtected = false
        var rawSemanticContent: GhosttyCellSemanticContent = GHOSTTY_CELL_SEMANTIC_OUTPUT
        var written = 0

        let cellResult = COutputPointers.withPointers(
            &rawContent,
            &rawWidth,
            &hasHyperlink,
            &isProtected,
            &rawSemanticContent
        ) { values in
            Self.cellDataKeys.withUnsafeBufferPointer { keyBuffer in
                ghostty_cell_get_multi(
                    rawCell,
                    keyBuffer.count,
                    keyBuffer.baseAddress,
                    values.baseAddress,
                    &written
                )
            }
        }
        try Self.check(cellResult)
        guard written == Self.cellDataKeys.count else {
            throw TerminalError.unexpectedResult
        }

        return (
            Self.cellWidth(from: rawWidth),
            rawContent == GHOSTTY_CELL_CONTENT_BG_COLOR_PALETTE ||
                rawContent == GHOSTTY_CELL_CONTENT_BG_COLOR_RGB,
            hasHyperlink,
            isProtected,
            Self.semanticContent(from: rawSemanticContent)
        )
    }

    private func resolvedColors(
        in rowCells: OpaquePointer,
        style: TerminalFrame.Style,
        hasExplicitBackground: Bool
    ) throws -> (foreground: TerminalFrame.RGBColor?, background: TerminalFrame.RGBColor?) {
        let foreground: TerminalFrame.RGBColor?
        if style.foreground != nil {
            var rawForeground = GhosttyColorRgb()
            let result = ghostty_render_state_row_cells_get(
                rowCells,
                GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR,
                &rawForeground
            )
            if result == GHOSTTY_SUCCESS {
                foreground = Self.color(from: rawForeground)
            } else if result == GHOSTTY_INVALID_VALUE {
                foreground = nil
            } else {
                try Self.check(result)
                foreground = nil
            }
        } else {
            foreground = nil
        }

        let background: TerminalFrame.RGBColor?
        if style.background != nil || hasExplicitBackground {
            var rawBackground = GhosttyColorRgb()
            let result = ghostty_render_state_row_cells_get(
                rowCells,
                GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR,
                &rawBackground
            )
            if result == GHOSTTY_SUCCESS {
                background = Self.color(from: rawBackground)
            } else if result == GHOSTTY_INVALID_VALUE {
                background = nil
            } else {
                try Self.check(result)
                background = nil
            }
        } else {
            background = nil
        }

        return (foreground, background)
    }

    private func cellText(in rowCells: OpaquePointer, graphemeCount: UInt32) throws -> String {
        guard graphemeCount > 0 else { return "" }

        let capacity = Int(graphemeCount) * 4
        if graphemeBuffer.count < capacity {
            graphemeBuffer = [UInt8](repeating: 0, count: capacity)
        }

        var byteCount = 0
        let result = graphemeBuffer.withUnsafeMutableBufferPointer { byteBuffer in
            var buffer = GhosttyBuffer()
            buffer.ptr = byteBuffer.baseAddress
            buffer.cap = capacity
            buffer.len = 0

            let result = ghostty_render_state_row_cells_get(
                rowCells,
                GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8,
                &buffer
            )
            byteCount = buffer.len
            return result
        }
        try Self.check(result)
        guard byteCount <= capacity else {
            throw TerminalError.unexpectedResult
        }
        return String(decoding: graphemeBuffer.prefix(byteCount), as: UTF8.self)
    }

    static func color(from raw: GhosttyColorRgb) -> TerminalFrame.RGBColor {
        .init(red: raw.r, green: raw.g, blue: raw.b)
    }

    private static func styleColor(from raw: GhosttyStyleColor) -> TerminalFrame.Color? {
        switch raw.tag {
        case GHOSTTY_STYLE_COLOR_PALETTE:
            return .palette(raw.value.palette)
        case GHOSTTY_STYLE_COLOR_RGB:
            return .rgb(color(from: raw.value.rgb))
        default:
            return nil
        }
    }

    private static func style(from raw: GhosttyStyle) -> TerminalFrame.Style {
        .init(
            foreground: styleColor(from: raw.fg_color),
            background: styleColor(from: raw.bg_color),
            underlineColor: styleColor(from: raw.underline_color),
            isBold: raw.bold,
            isItalic: raw.italic,
            isFaint: raw.faint,
            isBlinking: raw.blink,
            isInverse: raw.inverse,
            isInvisible: raw.invisible,
            isStrikethrough: raw.strikethrough,
            isOverlined: raw.overline,
            underline: underline(from: raw.underline)
        )
    }

    private static func underline(from raw: Int32) -> TerminalFrame.Underline {
        switch raw {
        case 0: .none
        case 1: .single
        case 2: .double
        case 3: .curly
        case 4: .dotted
        case 5: .dashed
        default: .unknown(raw)
        }
    }

    private static func cellWidth(from raw: GhosttyCellWide) -> TerminalFrame.CellWidth {
        switch raw {
        case GHOSTTY_CELL_WIDE_WIDE:
            return .wide
        case GHOSTTY_CELL_WIDE_SPACER_TAIL:
            return .spacerTail
        case GHOSTTY_CELL_WIDE_SPACER_HEAD:
            return .spacerHead
        default:
            return .narrow
        }
    }

    private static func semanticContent(
        from raw: GhosttyCellSemanticContent
    ) -> TerminalFrame.SemanticContent {
        switch raw {
        case GHOSTTY_CELL_SEMANTIC_INPUT:
            return .input
        case GHOSTTY_CELL_SEMANTIC_PROMPT:
            return .prompt
        default:
            return .output
        }
    }

    static func semanticPrompt(
        from raw: GhosttyRowSemanticPrompt
    ) -> TerminalFrame.SemanticPrompt {
        switch raw {
        case GHOSTTY_ROW_SEMANTIC_PROMPT:
            return .primary
        case GHOSTTY_ROW_SEMANTIC_PROMPT_CONTINUATION:
            return .continuation
        default:
            return .none
        }
    }

    static func cursorStyle(
        from raw: GhosttyRenderStateCursorVisualStyle
    ) -> TerminalFrame.CursorStyle {
        switch raw {
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR:
            return .bar
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE:
            return .underline
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW:
            return .hollowBlock
        default:
            return .block
        }
    }

    static func check(_ result: GhosttyResult) throws {
        switch result {
        case GHOSTTY_SUCCESS:
            return
        case GHOSTTY_OUT_OF_MEMORY:
            throw TerminalError.outOfMemory
        case GHOSTTY_INVALID_VALUE:
            throw TerminalError.invalidValue
        case GHOSTTY_OUT_OF_SPACE:
            throw TerminalError.outOfSpace
        case GHOSTTY_NO_VALUE:
            throw TerminalError.noValue
        default:
            throw TerminalError.unexpectedResult
        }
    }
}
