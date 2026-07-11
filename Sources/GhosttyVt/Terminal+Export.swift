import GhosttyVtRaw

extension Terminal {
    /// Exports the active terminal screen using libghostty-vt's formatter.
    public func exportScreen(options: ExportOptions = .init()) throws -> Data {
        try withTerminalLock {
            var rawOptions = GhosttyFormatterTerminalOptions()
            rawOptions.size = MemoryLayout<GhosttyFormatterTerminalOptions>.size
            rawOptions.emit = Self.rawExportFormat(from: options.format)
            rawOptions.unwrap = options.unwrapSoftLines
            rawOptions.trim = options.trimTrailingWhitespace
            rawOptions.extra.size = MemoryLayout<GhosttyFormatterTerminalExtra>.size
            rawOptions.extra.screen.size = MemoryLayout<GhosttyFormatterScreenExtra>.size
            rawOptions.extra.palette = options.terminalState.palette
            rawOptions.extra.modes = options.terminalState.modes
            rawOptions.extra.scrolling_region = options.terminalState.scrollingRegion
            rawOptions.extra.tabstops = options.terminalState.tabStops
            rawOptions.extra.pwd = options.terminalState.workingDirectory
            rawOptions.extra.keyboard = options.terminalState.keyboard
            rawOptions.extra.screen.cursor = options.terminalState.screen.cursor
            rawOptions.extra.screen.style = options.terminalState.screen.style
            rawOptions.extra.screen.hyperlink = options.terminalState.screen.hyperlink
            rawOptions.extra.screen.protection = options.terminalState.screen.protection
            rawOptions.extra.screen.kitty_keyboard = options.terminalState.screen.kittyKeyboard
            rawOptions.extra.screen.charsets = options.terminalState.screen.characterSets

            var rawFormatter: OpaquePointer?
            try Self.check(ghostty_formatter_terminal_new(nil, &rawFormatter, handle, rawOptions))
            guard let rawFormatter else {
                throw TerminalError.unexpectedResult
            }
            defer { ghostty_formatter_free(rawFormatter) }

            return try formattedData { buffer, capacity, written in
                ghostty_formatter_format_buf(rawFormatter, buffer, capacity, written)
            }
        }
    }

    /// Exports the active selection. Throws `TerminalError.noValue` when none is active.
    public func exportSelection(options: ExportOptions = .init()) throws -> Data {
        try withTerminalLock {
            var rawOptions = GhosttyTerminalSelectionFormatOptions()
            rawOptions.size = MemoryLayout<GhosttyTerminalSelectionFormatOptions>.size
            rawOptions.emit = Self.rawExportFormat(from: options.format)
            rawOptions.unwrap = options.unwrapSoftLines
            rawOptions.trim = options.trimTrailingWhitespace

            return try formattedData { buffer, capacity, written in
                ghostty_terminal_selection_format_buf(handle, rawOptions, buffer, capacity, written)
            }
        }
    }

    private func formattedData(
        _ format: (UnsafeMutablePointer<UInt8>?, Int, UnsafeMutablePointer<Int>) -> GhosttyResult
    ) throws -> Data {
        var required = 0
        let query = format(nil, 0, &required)
        if query == GHOSTTY_SUCCESS {
            guard required == 0 else {
                throw TerminalError.unexpectedResult
            }
            return Data()
        }
        guard query == GHOSTTY_OUT_OF_SPACE else {
            try Self.check(query)
            throw TerminalError.unexpectedResult
        }

        var output = [UInt8](repeating: 0, count: required)
        var written = 0
        let result = output.withUnsafeMutableBufferPointer { buffer in
            format(buffer.baseAddress, buffer.count, &written)
        }
        try Self.check(result)
        guard written <= output.count else {
            throw TerminalError.unexpectedResult
        }
        return Data(output.prefix(written))
    }

    private static func rawExportFormat(from format: ExportFormat) -> GhosttyFormatterFormat {
        switch format {
        case .plain:
            return GHOSTTY_FORMATTER_FORMAT_PLAIN
        case .terminal:
            return GHOSTTY_FORMATTER_FORMAT_VT
        case .html:
            return GHOSTTY_FORMATTER_FORMAT_HTML
        }
    }
}
