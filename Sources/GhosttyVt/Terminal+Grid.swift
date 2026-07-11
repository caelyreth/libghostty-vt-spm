import GhosttyVtRaw

extension Terminal {
    private static let gridCellDataKeys: [GhosttyCellData] = [
        GHOSTTY_CELL_DATA_CONTENT_TAG,
        GHOSTTY_CELL_DATA_WIDE,
        GHOSTTY_CELL_DATA_HAS_HYPERLINK,
        GHOSTTY_CELL_DATA_PROTECTED,
        GHOSTTY_CELL_DATA_SEMANTIC_CONTENT,
    ]

    /// Copies cell content and metadata at a terminal point.
    ///
    /// This is for search, accessibility, and inspection. Use render updates
    /// for frame-rate rendering.
    public func cell(at point: GridPoint) throws -> GridCell {
        try withTerminalLock {
            var reference = try gridReference(at: point)
            return try gridCell(from: &reference)
        }
    }

    /// Creates an owned anchor that follows a cell through scrolling and reflow.
    public func makeGridAnchor(at point: GridPoint) throws -> GridAnchor {
        try GridAnchor(terminal: self, point: point)
    }

    /// An owned cell anchor for search results, marks, and restored positions.
    public final class GridAnchor: @unchecked Sendable {
        private let terminal: Terminal
        private let handle: OpaquePointer

        fileprivate init(terminal: Terminal, point: GridPoint) throws {
            var rawAnchor: OpaquePointer?
            try terminal.withTerminalLock {
                try Terminal.check(
                    ghostty_terminal_grid_ref_track(terminal.handle, Terminal.rawGridPoint(from: point), &rawAnchor)
                )
            }
            guard let rawAnchor else {
                throw TerminalError.unexpectedResult
            }
            self.terminal = terminal
            handle = rawAnchor
        }

        deinit {
            terminal.withTerminalLock {
                ghostty_tracked_grid_ref_free(handle)
            }
        }

        /// Returns whether Ghostty can still associate this anchor with a terminal cell.
        public var hasValue: Bool {
            terminal.withTerminalLock {
                ghostty_tracked_grid_ref_has_value(handle)
            }
        }

        /// Returns a copied coordinate when this anchor is representable in that space.
        public func point(in coordinateSpace: GridCoordinateSpace) throws -> GridPoint? {
            try terminal.withTerminalLock {
                var rawPoint = GhosttyPointCoordinate()
                let result = ghostty_tracked_grid_ref_point(
                    handle,
                    Terminal.rawGridCoordinateSpace(from: coordinateSpace),
                    &rawPoint
                )
                if result == GHOSTTY_NO_VALUE {
                    return nil
                }
                try Terminal.check(result)
                return .init(
                    column: rawPoint.x,
                    row: rawPoint.y,
                    coordinateSpace: coordinateSpace
                )
            }
        }

        /// Moves this anchor to a new cell in the terminal's currently active screen.
        public func move(to point: GridPoint) throws {
            try terminal.withTerminalLock {
                try Terminal.check(
                    ghostty_tracked_grid_ref_set(handle, terminal.handle, Terminal.rawGridPoint(from: point))
                )
            }
        }

        /// Copies the anchored cell's current content and metadata, if it remains valid.
        public func cell() throws -> GridCell? {
            try terminal.withTerminalLock {
                var reference = GhosttyGridRef()
                reference.size = MemoryLayout<GhosttyGridRef>.size
                let result = ghostty_tracked_grid_ref_snapshot(handle, &reference)
                if result == GHOSTTY_NO_VALUE {
                    return nil
                }
                try Terminal.check(result)
                return try terminal.gridCell(from: &reference)
            }
        }
    }

    static func rawGridPoint(from point: GridPoint) -> GhosttyPoint {
        var rawPoint = GhosttyPoint()
        rawPoint.tag = rawGridCoordinateSpace(from: point.coordinateSpace)
        rawPoint.value.coordinate = .init(x: point.column, y: point.row)
        return rawPoint
    }

    static func rawGridCoordinateSpace(
        from coordinateSpace: GridCoordinateSpace
    ) -> GhosttyPointTag {
        switch coordinateSpace {
        case .active:
            return GHOSTTY_POINT_TAG_ACTIVE
        case .viewport:
            return GHOSTTY_POINT_TAG_VIEWPORT
        case .screen:
            return GHOSTTY_POINT_TAG_SCREEN
        case .history:
            return GHOSTTY_POINT_TAG_HISTORY
        }
    }

    func gridReference(at point: GridPoint) throws -> GhosttyGridRef {
        var reference = GhosttyGridRef()
        reference.size = MemoryLayout<GhosttyGridRef>.size
        try Self.check(ghostty_terminal_grid_ref(handle, Self.rawGridPoint(from: point), &reference))
        return reference
    }

    func gridPoint(
        from reference: inout GhosttyGridRef,
        in coordinateSpace: GridCoordinateSpace
    ) throws -> GridPoint? {
        var rawPoint = GhosttyPointCoordinate()
        let result = ghostty_terminal_point_from_grid_ref(
            handle,
            &reference,
            Self.rawGridCoordinateSpace(from: coordinateSpace),
            &rawPoint
        )
        if result == GHOSTTY_NO_VALUE {
            return nil
        }
        try Self.check(result)
        return .init(column: rawPoint.x, row: rawPoint.y, coordinateSpace: coordinateSpace)
    }

    func gridRange(
        from selection: inout GhosttySelection,
        in coordinateSpace: GridCoordinateSpace
    ) throws -> GridRange {
        guard let start = try gridPoint(from: &selection.start, in: coordinateSpace),
              let end = try gridPoint(from: &selection.end, in: coordinateSpace) else {
            throw TerminalError.noValue
        }
        return .init(start: start, end: end, isRectangular: selection.rectangle)
    }

    func gridCell(from reference: inout GhosttyGridRef) throws -> GridCell {
        var rawCell: UInt64 = 0
        try Self.check(ghostty_grid_ref_cell(&reference, &rawCell))

        var rawStyle = GhosttyStyle()
        rawStyle.size = MemoryLayout<GhosttyStyle>.size
        try Self.check(ghostty_grid_ref_style(&reference, &rawStyle))

        var rawContent: GhosttyCellContentTag = GHOSTTY_CELL_CONTENT_CODEPOINT
        var rawWidth: GhosttyCellWide = GHOSTTY_CELL_WIDE_NARROW
        var hasHyperlink = false
        var isProtected = false
        var rawSemanticContent: GhosttyCellSemanticContent = GHOSTTY_CELL_SEMANTIC_OUTPUT
        let metadataResult = COutputPointers.withPointers(
            &rawContent,
            &rawWidth,
            &hasHyperlink,
            &isProtected,
            &rawSemanticContent
        ) { values in
            Self.gridCellDataKeys.withUnsafeBufferPointer { keys in
                ghostty_cell_get_multi(rawCell, keys.count, keys.baseAddress, values.baseAddress, nil)
            }
        }
        try Self.check(metadataResult)

        return .init(
            text: try gridReferenceText(&reference),
            width: Self.cellWidth(from: rawWidth),
            style: Self.style(from: rawStyle),
            hyperlink: hasHyperlink ? try gridReferenceHyperlink(&reference) : nil,
            isBackgroundColorOnly: rawContent == GHOSTTY_CELL_CONTENT_BG_COLOR_PALETTE ||
                rawContent == GHOSTTY_CELL_CONTENT_BG_COLOR_RGB,
            isProtected: isProtected,
            semanticContent: Self.semanticContent(from: rawSemanticContent)
        )
    }

    private func gridReferenceText(_ reference: inout GhosttyGridRef) throws -> String {
        var required = 0
        let query = ghostty_grid_ref_graphemes(&reference, nil, 0, &required)
        if query == GHOSTTY_SUCCESS {
            guard required == 0 else { throw TerminalError.unexpectedResult }
            return ""
        }
        guard query == GHOSTTY_OUT_OF_SPACE else {
            try Self.check(query)
            throw TerminalError.unexpectedResult
        }

        var codepoints = [UInt32](repeating: 0, count: required)
        var written = 0
        let result = codepoints.withUnsafeMutableBufferPointer { buffer in
            ghostty_grid_ref_graphemes(&reference, buffer.baseAddress, buffer.count, &written)
        }
        try Self.check(result)
        guard written <= codepoints.count else { throw TerminalError.unexpectedResult }

        var scalars = String.UnicodeScalarView()
        for codepoint in codepoints.prefix(written) {
            guard let scalar = Unicode.Scalar(codepoint) else {
                throw TerminalError.unexpectedResult
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private func gridReferenceHyperlink(_ reference: inout GhosttyGridRef) throws -> String? {
        var required = 0
        let query = ghostty_grid_ref_hyperlink_uri(&reference, nil, 0, &required)
        if query == GHOSTTY_SUCCESS {
            guard required == 0 else { throw TerminalError.unexpectedResult }
            return nil
        }
        guard query == GHOSTTY_OUT_OF_SPACE else {
            try Self.check(query)
            throw TerminalError.unexpectedResult
        }

        var output = [UInt8](repeating: 0, count: required)
        var written = 0
        let result = output.withUnsafeMutableBufferPointer { buffer in
            ghostty_grid_ref_hyperlink_uri(&reference, buffer.baseAddress, buffer.count, &written)
        }
        try Self.check(result)
        guard written <= output.count else { throw TerminalError.unexpectedResult }
        return String(decoding: output.prefix(written), as: UTF8.self)
    }
}
