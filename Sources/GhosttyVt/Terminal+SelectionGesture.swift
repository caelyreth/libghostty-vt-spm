import GhosttyVtRaw

extension Terminal {
    /// Creates a reusable gesture interpreter for one terminal interaction stream.
    public func makeSelectionGesture(
        configuration: SelectionGestureConfiguration = .init()
    ) throws -> SelectionGesture {
        guard configuration.maximumRepeatDistance.isFinite, configuration.maximumRepeatDistance >= 0 else {
            throw TerminalError.invalidSelectionGestureConfiguration
        }
        return try SelectionGesture(terminal: self, configuration: configuration)
    }

    /// Owns Ghostty's state for one selection interaction stream.
    public final class SelectionGesture: @unchecked Sendable {
        private let terminal: Terminal
        private let handle: OpaquePointer
        private let pressEvent: OpaquePointer
        private let dragEvent: OpaquePointer
        private let releaseEvent: OpaquePointer
        private let autoscrollEvent: OpaquePointer
        private let deepPressEvent: OpaquePointer
        private let configuration: SelectionGestureConfiguration

        fileprivate init(terminal: Terminal, configuration: SelectionGestureConfiguration) throws {
            var rawGesture: OpaquePointer?
            var rawPress: OpaquePointer?
            var rawDrag: OpaquePointer?
            var rawRelease: OpaquePointer?
            var rawAutoscroll: OpaquePointer?
            var rawDeepPress: OpaquePointer?
            do {
                try Terminal.check(ghostty_selection_gesture_new(nil, &rawGesture))
                try Terminal.check(
                    ghostty_selection_gesture_event_new(
                        nil,
                        &rawPress,
                        GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS
                    )
                )
                try Terminal.check(
                    ghostty_selection_gesture_event_new(
                        nil,
                        &rawDrag,
                        GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG
                    )
                )
                try Terminal.check(
                    ghostty_selection_gesture_event_new(
                        nil,
                        &rawRelease,
                        GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE
                    )
                )
                try Terminal.check(
                    ghostty_selection_gesture_event_new(
                        nil,
                        &rawAutoscroll,
                        GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_AUTOSCROLL_TICK
                    )
                )
                try Terminal.check(
                    ghostty_selection_gesture_event_new(
                        nil,
                        &rawDeepPress,
                        GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DEEP_PRESS
                    )
                )
                guard
                    let rawGesture,
                    let rawPress,
                    let rawDrag,
                    let rawRelease,
                    let rawAutoscroll,
                    let rawDeepPress
                else {
                    throw TerminalError.unexpectedResult
                }

                self.terminal = terminal
                handle = rawGesture
                pressEvent = rawPress
                dragEvent = rawDrag
                releaseEvent = rawRelease
                autoscrollEvent = rawAutoscroll
                deepPressEvent = rawDeepPress
                self.configuration = configuration
            } catch {
                ghostty_selection_gesture_event_free(rawDeepPress)
                ghostty_selection_gesture_event_free(rawAutoscroll)
                ghostty_selection_gesture_event_free(rawRelease)
                ghostty_selection_gesture_event_free(rawDrag)
                ghostty_selection_gesture_event_free(rawPress)
                ghostty_selection_gesture_free(rawGesture, terminal.handle)
                throw error
            }
        }

        deinit {
            terminal.withTerminalLock {
                ghostty_selection_gesture_event_free(deepPressEvent)
                ghostty_selection_gesture_event_free(autoscrollEvent)
                ghostty_selection_gesture_event_free(releaseEvent)
                ghostty_selection_gesture_event_free(dragEvent)
                ghostty_selection_gesture_event_free(pressEvent)
                ghostty_selection_gesture_free(handle, terminal.handle)
            }
        }

        /// Begins a click sequence at a viewport cell.
        public func press(
            at point: ViewportPoint,
            position: SurfacePosition,
            timestampNanoseconds: UInt64? = nil
        ) throws -> SelectionGestureState {
            try terminal.withTerminalLock {
                var reference = try terminal.gridReference(at: point)
                var rawPosition = GhosttySurfacePosition(x: position.x, y: position.y)
                var repeatDistance = configuration.maximumRepeatDistance
                var repeatInterval = configuration.maximumRepeatIntervalNanoseconds
                var behaviors = Self.rawBehaviors(from: configuration)

                try set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &reference)
                try set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &rawPosition)
                try set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_DISTANCE, &repeatDistance)
                try set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_INTERVAL_NS, &repeatInterval)
                try set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_BEHAVIORS, &behaviors)
                if var timestampNanoseconds {
                    try set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS, &timestampNanoseconds)
                } else {
                    try clear(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS)
                }
                return try apply(pressEvent)
            }
        }

        /// Extends the active gesture to a viewport cell.
        public func drag(
            to point: ViewportPoint,
            position: SurfacePosition,
            geometry: SelectionGestureGeometry,
            rectangular: Bool = false
        ) throws -> SelectionGestureState {
            try terminal.withTerminalLock {
                var reference = try terminal.gridReference(at: point)
                var rawPosition = GhosttySurfacePosition(x: position.x, y: position.y)
                var rawGeometry = try Self.rawGeometry(from: geometry)
                var rectangular = rectangular

                try set(dragEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &reference)
                try set(dragEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &rawPosition)
                try set(dragEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY, &rawGeometry)
                try set(dragEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_RECTANGLE, &rectangular)
                return try apply(dragEvent)
            }
        }

        /// Finishes the active click sequence. A nil point records release outside the grid.
        public func release(at point: ViewportPoint? = nil) throws -> SelectionGestureState {
            try terminal.withTerminalLock {
                if let point {
                    var reference = try terminal.gridReference(at: point)
                    try set(releaseEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &reference)
                } else {
                    try clear(releaseEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF)
                }
                return try apply(releaseEvent)
            }
        }

        /// Updates selection while the host autoscrolls its viewport during a drag.
        public func autoscroll(
            viewport: ViewportPoint,
            position: SurfacePosition,
            geometry: SelectionGestureGeometry,
            rectangular: Bool = false
        ) throws -> SelectionGestureState {
            try terminal.withTerminalLock {
                var rawViewport = GhosttyPointCoordinate(x: viewport.column, y: viewport.row)
                var rawPosition = GhosttySurfacePosition(x: position.x, y: position.y)
                var rawGeometry = try Self.rawGeometry(from: geometry)
                var rectangular = rectangular

                try set(autoscrollEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_VIEWPORT, &rawViewport)
                try set(autoscrollEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &rawPosition)
                try set(autoscrollEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY, &rawGeometry)
                try set(autoscrollEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_RECTANGLE, &rectangular)
                return try apply(autoscrollEvent)
            }
        }

        /// Selects the word around the active click anchor.
        public func deepPress() throws -> SelectionGestureState {
            try terminal.withTerminalLock {
                try apply(deepPressEvent)
            }
        }

        /// Cancels the active click sequence and releases its tracked anchors.
        public func reset() {
            terminal.withTerminalLock {
                ghostty_selection_gesture_reset(handle, terminal.handle)
            }
        }

        private func apply(_ event: OpaquePointer) throws -> SelectionGestureState {
            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            let result = ghostty_selection_gesture_event(handle, terminal.handle, event, &selection)
            let changed: Bool
            if result == GHOSTTY_SUCCESS {
                try terminal.installSelection(&selection)
                changed = true
            } else if result == GHOSTTY_NO_VALUE {
                changed = false
            } else {
                try Terminal.check(result)
                changed = false
            }
            return try state(selectionChanged: changed)
        }

        private func state(selectionChanged: Bool) throws -> SelectionGestureState {
            var clickCount: UInt8 = 0
            var dragged = false
            var rawBehavior: GhosttySelectionGestureBehavior = GHOSTTY_SELECTION_GESTURE_BEHAVIOR_CELL
            var rawAutoscroll: GhosttySelectionGestureAutoscroll = GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_NONE
            try Terminal.check(
                ghostty_selection_gesture_get(
                    handle,
                    terminal.handle,
                    GHOSTTY_SELECTION_GESTURE_DATA_CLICK_COUNT,
                    &clickCount
                )
            )
            try Terminal.check(
                ghostty_selection_gesture_get(
                    handle,
                    terminal.handle,
                    GHOSTTY_SELECTION_GESTURE_DATA_DRAGGED,
                    &dragged
                )
            )
            try Terminal.check(
                ghostty_selection_gesture_get(
                    handle,
                    terminal.handle,
                    GHOSTTY_SELECTION_GESTURE_DATA_BEHAVIOR,
                    &rawBehavior
                )
            )
            try Terminal.check(
                ghostty_selection_gesture_get(
                    handle,
                    terminal.handle,
                    GHOSTTY_SELECTION_GESTURE_DATA_AUTOSCROLL,
                    &rawAutoscroll
                )
            )
            return .init(
                clickCount: clickCount,
                hasDragged: dragged,
                behavior: Self.behavior(from: rawBehavior),
                autoscroll: Self.autoscroll(from: rawAutoscroll),
                selectionChanged: selectionChanged
            )
        }

        private func set<Value>(
            _ event: OpaquePointer,
            _ option: GhosttySelectionGestureEventOption,
            _ value: inout Value
        ) throws {
            try Terminal.check(ghostty_selection_gesture_event_set(event, option, &value))
        }

        private func clear(_ event: OpaquePointer, _ option: GhosttySelectionGestureEventOption) throws {
            try Terminal.check(ghostty_selection_gesture_event_set(event, option, nil))
        }

        private static func rawBehaviors(
            from configuration: SelectionGestureConfiguration
        ) -> GhosttySelectionGestureBehaviors {
            .init(
                single_click: rawBehavior(from: configuration.singleClick),
                double_click: rawBehavior(from: configuration.doubleClick),
                triple_click: rawBehavior(from: configuration.tripleClick)
            )
        }

        private static func rawGeometry(
            from geometry: SelectionGestureGeometry
        ) throws -> GhosttySelectionGestureGeometry {
            guard geometry.columns > 0, geometry.cellWidth > 0, geometry.screenHeight > 0 else {
                throw TerminalError.invalidSelectionGestureGeometry
            }
            return .init(
                columns: geometry.columns,
                cell_width: geometry.cellWidth,
                padding_left: geometry.paddingLeft,
                screen_height: geometry.screenHeight
            )
        }

        private static func rawBehavior(
            from behavior: SelectionGestureBehavior
        ) -> GhosttySelectionGestureBehavior {
            switch behavior {
            case .cell:
                return GHOSTTY_SELECTION_GESTURE_BEHAVIOR_CELL
            case .word:
                return GHOSTTY_SELECTION_GESTURE_BEHAVIOR_WORD
            case .line:
                return GHOSTTY_SELECTION_GESTURE_BEHAVIOR_LINE
            case .output:
                return GHOSTTY_SELECTION_GESTURE_BEHAVIOR_OUTPUT
            }
        }

        private static func behavior(
            from raw: GhosttySelectionGestureBehavior
        ) -> SelectionGestureBehavior {
            switch raw {
            case GHOSTTY_SELECTION_GESTURE_BEHAVIOR_WORD:
                return .word
            case GHOSTTY_SELECTION_GESTURE_BEHAVIOR_LINE:
                return .line
            case GHOSTTY_SELECTION_GESTURE_BEHAVIOR_OUTPUT:
                return .output
            default:
                return .cell
            }
        }

        private static func autoscroll(
            from raw: GhosttySelectionGestureAutoscroll
        ) -> SelectionAutoscroll {
            switch raw {
            case GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_UP:
                return .up
            case GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_DOWN:
                return .down
            default:
                return .none
            }
        }
    }
}
