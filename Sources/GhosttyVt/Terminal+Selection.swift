import GhosttyVtRaw

extension Terminal {
    /// Selects a range in any terminal coordinate space accepted by libghostty-vt.
    public func select(_ range: GridRange) throws {
        guard range.start.coordinateSpace == range.end.coordinateSpace else {
            throw TerminalError.invalidValue
        }
        try withTerminalLock {
            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            selection.start = try gridReference(at: range.start)
            selection.end = try gridReference(at: range.end)
            selection.rectangle = range.isRectangular
            try installSelection(&selection)
        }
    }

    /// Selects the inclusive viewport range between two cells.
    public func select(
        from start: ViewportPoint,
        to end: ViewportPoint,
        rectangular: Bool = false
    ) throws {
        try select(.init(
            start: .init(column: start.column, row: start.row, coordinateSpace: .viewport),
            end: .init(column: end.column, row: end.row, coordinateSpace: .viewport),
            isRectangular: rectangular
        ))
    }

    /// Selects the word at a viewport cell using libghostty-vt's word rules.
    public func selectWord(at point: ViewportPoint) throws {
        try withTerminalLock {
            var options = GhosttyTerminalSelectWordOptions()
            options.size = MemoryLayout<GhosttyTerminalSelectWordOptions>.size
            options.ref = try gridReference(at: point)

            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            try Self.check(ghostty_terminal_select_word(handle, &options, &selection))
            try installSelection(&selection)
        }
    }

    /// Selects the line at a viewport cell using libghostty-vt's line rules.
    public func selectLine(
        at point: ViewportPoint,
        semanticPromptBoundary: Bool = false
    ) throws {
        try withTerminalLock {
            var options = GhosttyTerminalSelectLineOptions()
            options.size = MemoryLayout<GhosttyTerminalSelectLineOptions>.size
            options.ref = try gridReference(at: point)
            options.semantic_prompt_boundary = semanticPromptBoundary

            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            try Self.check(ghostty_terminal_select_line(handle, &options, &selection))
            try installSelection(&selection)
        }
    }

    /// Selects all selectable content on the active screen.
    public func selectAll() throws {
        try withTerminalLock {
            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            try Self.check(ghostty_terminal_select_all(handle, &selection))
            try installSelection(&selection)
        }
    }

    /// Selects the semantic command output containing a viewport cell.
    public func selectCommandOutput(at point: ViewportPoint) throws {
        try withTerminalLock {
            let reference = try gridReference(at: point)
            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            try Self.check(ghostty_terminal_select_output(handle, reference, &selection))
            try installSelection(&selection)
        }
    }

    /// Clears the active terminal selection.
    public func clearSelection() throws {
        try withTerminalLock {
            try Self.check(ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SELECTION, nil))
        }
    }

    /// Returns the active selection as a copied range in screen coordinates.
    public func selection() throws -> GridRange? {
        try withTerminalLock {
            guard var selection = try activeSelection() else { return nil }
            return try gridRange(from: &selection, in: .screen)
        }
    }

    /// Returns the active selection's endpoint direction.
    public func selectionOrder() throws -> SelectionOrder? {
        try withTerminalLock {
            guard var selection = try activeSelection() else { return nil }
            var rawOrder: GhosttySelectionOrder = GHOSTTY_SELECTION_ORDER_FORWARD
            try Self.check(ghostty_terminal_selection_order(handle, &selection, &rawOrder))
            return Self.selectionOrder(from: rawOrder)
        }
    }

    /// Moves the active selection's logical end using terminal keyboard-selection semantics.
    @discardableResult
    public func adjustSelection(_ adjustment: SelectionAdjustment) throws -> GridRange {
        try withTerminalLock {
            guard var selection = try activeSelection() else {
                throw TerminalError.noValue
            }
            try Self.check(
                ghostty_terminal_selection_adjust(handle, &selection, Self.rawSelectionAdjustment(from: adjustment))
            )
            try installSelection(&selection)
            return try gridRange(from: &selection, in: .screen)
        }
    }

    /// Returns whether a terminal point lies within the active selection.
    public func selectionContains(_ point: GridPoint) throws -> Bool {
        try withTerminalLock {
            guard var selection = try activeSelection() else { return false }
            var contains = false
            try Self.check(
                ghostty_terminal_selection_contains(handle, &selection, Self.rawGridPoint(from: point), &contains)
            )
            return contains
        }
    }

    /// Returns the active selection as clipboard-ready plain text.
    public func copySelection() throws -> String {
        try withTerminalLock {
            var options = GhosttyTerminalSelectionFormatOptions()
            options.size = MemoryLayout<GhosttyTerminalSelectionFormatOptions>.size
            options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN
            options.unwrap = true
            options.trim = true

            var required = 0
            let query = ghostty_terminal_selection_format_buf(
                handle,
                options,
                nil,
                0,
                &required
            )
            if query == GHOSTTY_SUCCESS {
                guard required == 0 else {
                    throw TerminalError.unexpectedResult
                }
                return ""
            }
            guard query == GHOSTTY_OUT_OF_SPACE else {
                try Self.check(query)
                throw TerminalError.unexpectedResult
            }

            var output = [UInt8](repeating: 0, count: required)
            var written = 0
            let result = output.withUnsafeMutableBufferPointer { buffer in
                ghostty_terminal_selection_format_buf(
                    handle,
                    options,
                    buffer.baseAddress,
                    buffer.count,
                    &written
                )
            }
            try Self.check(result)
            guard written <= output.count else {
                throw TerminalError.unexpectedResult
            }
            return String(decoding: output.prefix(written), as: UTF8.self)
        }
    }

    /// Returns the hyperlink URI at a viewport cell, if the cell has one.
    public func hyperlink(at point: ViewportPoint) throws -> String? {
        try withTerminalLock {
            var reference = try gridReference(at: point)
            var required = 0
            let query = ghostty_grid_ref_hyperlink_uri(&reference, nil, 0, &required)
            if query == GHOSTTY_SUCCESS {
                guard required == 0 else {
                    throw TerminalError.unexpectedResult
                }
                return nil
            }
            guard query == GHOSTTY_OUT_OF_SPACE else {
                try Self.check(query)
                throw TerminalError.unexpectedResult
            }

            var output = [UInt8](repeating: 0, count: required)
            var written = 0
            let result = output.withUnsafeMutableBufferPointer { buffer in
                ghostty_grid_ref_hyperlink_uri(
                    &reference,
                    buffer.baseAddress,
                    buffer.count,
                    &written
                )
            }
            try Self.check(result)
            guard written <= output.count else {
                throw TerminalError.unexpectedResult
            }
            return String(decoding: output.prefix(written), as: UTF8.self)
        }
    }

    func gridReference(at point: ViewportPoint) throws -> GhosttyGridRef {
        try gridReference(at: .init(column: point.column, row: point.row, coordinateSpace: .viewport))
    }

    func installSelection(_ selection: inout GhosttySelection) throws {
        try Self.check(ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SELECTION, &selection))
    }

    private func activeSelection() throws -> GhosttySelection? {
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        let result = ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_SELECTION, &selection)
        if result == GHOSTTY_NO_VALUE {
            return nil
        }
        try Self.check(result)
        return selection
    }

    private static func rawSelectionAdjustment(
        from adjustment: SelectionAdjustment
    ) -> GhosttySelectionAdjust {
        switch adjustment {
        case .left:
            return GHOSTTY_SELECTION_ADJUST_LEFT
        case .right:
            return GHOSTTY_SELECTION_ADJUST_RIGHT
        case .up:
            return GHOSTTY_SELECTION_ADJUST_UP
        case .down:
            return GHOSTTY_SELECTION_ADJUST_DOWN
        case .home:
            return GHOSTTY_SELECTION_ADJUST_HOME
        case .end:
            return GHOSTTY_SELECTION_ADJUST_END
        case .pageUp:
            return GHOSTTY_SELECTION_ADJUST_PAGE_UP
        case .pageDown:
            return GHOSTTY_SELECTION_ADJUST_PAGE_DOWN
        case .beginningOfLine:
            return GHOSTTY_SELECTION_ADJUST_BEGINNING_OF_LINE
        case .endOfLine:
            return GHOSTTY_SELECTION_ADJUST_END_OF_LINE
        }
    }

    private static func selectionOrder(from rawOrder: GhosttySelectionOrder) -> SelectionOrder {
        switch rawOrder {
        case GHOSTTY_SELECTION_ORDER_REVERSE:
            return .reverse
        case GHOSTTY_SELECTION_ORDER_MIRRORED_FORWARD:
            return .mirroredForward
        case GHOSTTY_SELECTION_ORDER_MIRRORED_REVERSE:
            return .mirroredReverse
        default:
            return .forward
        }
    }
}
