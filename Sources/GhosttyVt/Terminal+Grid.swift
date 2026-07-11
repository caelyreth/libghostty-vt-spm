import GhosttyVtRaw

extension Terminal {
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
}
