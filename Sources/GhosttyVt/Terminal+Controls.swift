import GhosttyVtRaw

extension Terminal {
    private static let statusDataKeys: [GhosttyTerminalData] = [
        GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN,
        GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS,
        GHOSTTY_TERMINAL_DATA_SCROLLBAR,
        GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING,
        GHOSTTY_TERMINAL_DATA_VIEWPORT_ACTIVE,
    ]

    /// Moves the visible viewport without mutating terminal content.
    public func scroll(to position: ViewportPosition) throws {
        try withTerminalLock {
            var behavior = GhosttyTerminalScrollViewport()
            switch position {
            case .top:
                behavior.tag = GHOSTTY_SCROLL_VIEWPORT_TOP
            case .bottom:
                behavior.tag = GHOSTTY_SCROLL_VIEWPORT_BOTTOM
            case .delta(let amount):
                behavior.tag = GHOSTTY_SCROLL_VIEWPORT_DELTA
                behavior.value.delta = amount
            case .row(let offset):
                guard offset >= 0 else {
                    throw TerminalError.invalidViewportRow
                }
                behavior.tag = GHOSTTY_SCROLL_VIEWPORT_ROW
                behavior.value.row = offset
            }
            ghostty_terminal_scroll_viewport(handle, behavior)
        }
    }

    /// Sets the embedder-owned terminal color defaults.
    public func setDefaultTheme(_ theme: DefaultTheme) throws {
        guard theme.palette?.count == 256 || theme.palette == nil else {
            throw TerminalError.invalidPalette
        }

        try withTerminalLock {
            try setDefaultColor(theme.foreground, option: GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND)
            try setDefaultColor(theme.background, option: GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND)
            try setDefaultColor(theme.cursor, option: GHOSTTY_TERMINAL_OPT_COLOR_CURSOR)

            guard let palette = theme.palette else {
                try Self.check(ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, nil))
                return
            }

            let rawPalette = palette.map(Self.rawColor(from:))
            let result = rawPalette.withUnsafeBufferPointer { buffer in
                ghostty_terminal_set(
                    handle,
                    GHOSTTY_TERMINAL_OPT_COLOR_PALETTE,
                    UnsafeRawPointer(buffer.baseAddress!)
                )
            }
            try Self.check(result)
        }
    }

    /// Sets the cursor defaults restored by a DECSCUSR reset sequence.
    public func setCursorDefaults(_ defaults: CursorDefaults) throws {
        try withTerminalLock {
            if let style = defaults.style {
                var rawStyle = Self.rawCursorStyle(from: style)
                try Self.check(
                    ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_STYLE, &rawStyle)
                )
            } else {
                try Self.check(
                    ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_STYLE, nil)
                )
            }

            if var isBlinking = defaults.isBlinking {
                try Self.check(
                    ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_BLINK, &isBlinking)
                )
            } else {
                try Self.check(
                    ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_BLINK, nil)
                )
            }
        }
    }

    /// Bounds buffered APC input before protocol parsing allocates memory.
    public func setAPCBufferLimits(_ limits: APCBufferLimits) throws {
        guard limits.allProtocols.map({ $0 >= 0 }) ?? true,
              limits.kittyGraphics.map({ $0 >= 0 }) ?? true else {
            throw TerminalError.invalidAPCBufferLimit
        }

        try withTerminalLock {
            try setAPCBufferLimit(limits.allProtocols, option: GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES)
            try setAPCBufferLimit(limits.kittyGraphics, option: GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES_KITTY)
        }
    }

    /// Enables or disables Ghostty's Glyph Protocol APC handling.
    public func setGlyphProtocolEnabled(_ enabled: Bool) throws {
        try withTerminalLock {
            var enabled = enabled
            try Self.check(ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_GLYPH_PROTOCOL, &enabled))
        }
    }

    /// Overrides the terminal title. Pass `nil` to clear the override.
    public func setTitle(_ title: String?) throws {
        try withTerminalLock {
            try setTerminalString(title, option: GHOSTTY_TERMINAL_OPT_TITLE)
        }
    }

    /// Overrides the terminal working directory. Pass `nil` to clear the override.
    public func setWorkingDirectory(_ directory: String?) throws {
        try withTerminalLock {
            try setTerminalString(directory, option: GHOSTTY_TERMINAL_OPT_PWD)
        }
    }

    /// Returns whether a supported ANSI or DEC-private terminal mode is enabled.
    public func isModeEnabled(_ mode: Mode) throws -> Bool {
        try withTerminalLock {
            var enabled = false
            try Self.check(ghostty_terminal_mode_get(handle, Self.rawMode(from: mode), &enabled))
            return enabled
        }
    }

    /// Sets a supported ANSI or DEC-private terminal mode.
    public func setMode(_ mode: Mode, enabled: Bool) throws {
        try withTerminalLock {
            try Self.check(ghostty_terminal_mode_set(handle, Self.rawMode(from: mode), enabled))
        }
    }

    /// Captures Swift-owned terminal state for UI and input policy.
    public func status() throws -> Status {
        try withTerminalLock {
            var rawScreen: GhosttyTerminalScreen = GHOSTTY_TERMINAL_SCREEN_PRIMARY
            var rawKittyFlags: UInt8 = 0
            var rawScrollbar = GhosttyTerminalScrollbar()
            var mouseTracking = false
            var viewportActive = true
            var written = 0

            let result = COutputPointers.withPointers(
                &rawScreen,
                &rawKittyFlags,
                &rawScrollbar,
                &mouseTracking,
                &viewportActive
            ) { values in
                Self.statusDataKeys.withUnsafeBufferPointer { keyBuffer in
                    ghostty_terminal_get_multi(
                        handle,
                        keyBuffer.count,
                        keyBuffer.baseAddress,
                        values.baseAddress,
                        &written
                    )
                }
            }
            try Self.check(result)
            guard written == Self.statusDataKeys.count else {
                throw TerminalError.unexpectedResult
            }

            var scrollbackRows = 0
            try Self.check(
                ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &scrollbackRows)
            )

            let title = terminalString(from: handle, data: GHOSTTY_TERMINAL_DATA_TITLE) ?? ""
            let directory = terminalString(from: handle, data: GHOSTTY_TERMINAL_DATA_PWD)

            return .init(
                activeScreen: rawScreen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE ? .alternate : .primary,
                scrollbar: .init(
                    totalRows: rawScrollbar.total,
                    offset: rawScrollbar.offset,
                    visibleRows: rawScrollbar.len
                ),
                scrollbackRows: scrollbackRows,
                isViewportActive: viewportActive,
                isMouseReportingEnabled: mouseTracking,
                kittyKeyboardFlags: .init(rawValue: rawKittyFlags),
                title: title,
                workingDirectory: directory?.isEmpty == true ? nil : directory
            )
        }
    }

    private func setDefaultColor(
        _ color: TerminalFrame.RGBColor?,
        option: GhosttyTerminalOption
    ) throws {
        guard let color else {
            try Self.check(ghostty_terminal_set(handle, option, nil))
            return
        }

        var rawColor = Self.rawColor(from: color)
        try Self.check(ghostty_terminal_set(handle, option, &rawColor))
    }

    private func setAPCBufferLimit(_ limit: Int?, option: GhosttyTerminalOption) throws {
        guard var limit else {
            try Self.check(ghostty_terminal_set(handle, option, nil))
            return
        }
        try Self.check(ghostty_terminal_set(handle, option, &limit))
    }

    private func setTerminalString(_ value: String?, option: GhosttyTerminalOption) throws {
        guard var value else {
            try Self.check(ghostty_terminal_set(handle, option, nil))
            return
        }
        try value.withUTF8 { utf8 in
            var rawValue = GhosttyString(ptr: utf8.baseAddress, len: utf8.count)
            try Self.check(ghostty_terminal_set(handle, option, &rawValue))
        }
    }

    private static func rawColor(from color: TerminalFrame.RGBColor) -> GhosttyColorRgb {
        .init(r: color.red, g: color.green, b: color.blue)
    }

    private static func rawCursorStyle(
        from style: TerminalFrame.CursorStyle
    ) -> GhosttyTerminalCursorStyle {
        switch style {
        case .bar:
            return GHOSTTY_TERMINAL_CURSOR_STYLE_BAR
        case .underline:
            return GHOSTTY_TERMINAL_CURSOR_STYLE_UNDERLINE
        case .hollowBlock:
            return GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK_HOLLOW
        case .block:
            return GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK
        }
    }

    private static func rawMode(from mode: Mode) -> GhosttyMode {
        ghostty_mode_new(mode.value, mode.isANSI)
    }
}
