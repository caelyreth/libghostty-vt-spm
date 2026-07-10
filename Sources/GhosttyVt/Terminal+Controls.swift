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

    private static func rawColor(from color: TerminalFrame.RGBColor) -> GhosttyColorRgb {
        .init(r: color.red, g: color.green, b: color.blue)
    }
}
