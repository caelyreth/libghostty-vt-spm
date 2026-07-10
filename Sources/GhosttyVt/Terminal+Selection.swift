import GhosttyVtRaw

extension Terminal {
    /// Selects the inclusive viewport range between two cells.
    public func select(
        from start: ViewportPoint,
        to end: ViewportPoint,
        rectangular: Bool = false
    ) throws {
        try withTerminalLock {
            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            selection.start = try gridReference(at: start)
            selection.end = try gridReference(at: end)
            selection.rectangle = rectangular
            try installSelection(&selection)
        }
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
        var rawPoint = GhosttyPoint()
        rawPoint.tag = GHOSTTY_POINT_TAG_VIEWPORT
        rawPoint.value.coordinate = .init(x: point.column, y: point.row)

        var reference = GhosttyGridRef()
        reference.size = MemoryLayout<GhosttyGridRef>.size
        try Self.check(ghostty_terminal_grid_ref(handle, rawPoint, &reference))
        return reference
    }

    func installSelection(_ selection: inout GhosttySelection) throws {
        try Self.check(ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SELECTION, &selection))
    }
}
