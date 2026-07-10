extension Terminal {
    /// A cell coordinate in the visible terminal viewport.
    public struct ViewportPoint: Sendable, Equatable {
        public let column: UInt16
        public let row: UInt32

        public init(column: UInt16, row: UInt32) {
            self.column = column
            self.row = row
        }
    }

    public struct SurfacePosition: Sendable, Equatable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct SelectionGestureGeometry: Sendable, Equatable {
        public let columns: UInt32
        public let cellWidth: UInt32
        public let paddingLeft: UInt32
        public let screenHeight: UInt32

        public init(columns: UInt32, cellWidth: UInt32, paddingLeft: UInt32 = 0, screenHeight: UInt32) {
            self.columns = columns
            self.cellWidth = cellWidth
            self.paddingLeft = paddingLeft
            self.screenHeight = screenHeight
        }
    }

    public enum SelectionGestureBehavior: Sendable, Equatable {
        case cell
        case word
        case line
        case output
    }

    public enum SelectionAutoscroll: Sendable, Equatable {
        case none
        case up
        case down
    }

    public struct SelectionGestureConfiguration: Sendable, Equatable {
        public let singleClick: SelectionGestureBehavior
        public let doubleClick: SelectionGestureBehavior
        public let tripleClick: SelectionGestureBehavior
        public let maximumRepeatDistance: Double
        public let maximumRepeatIntervalNanoseconds: UInt64

        public init(
            singleClick: SelectionGestureBehavior = .cell,
            doubleClick: SelectionGestureBehavior = .word,
            tripleClick: SelectionGestureBehavior = .line,
            maximumRepeatDistance: Double = 5,
            maximumRepeatIntervalNanoseconds: UInt64 = 500_000_000
        ) {
            self.singleClick = singleClick
            self.doubleClick = doubleClick
            self.tripleClick = tripleClick
            self.maximumRepeatDistance = maximumRepeatDistance
            self.maximumRepeatIntervalNanoseconds = maximumRepeatIntervalNanoseconds
        }
    }

    public struct SelectionGestureState: Sendable, Equatable {
        public let clickCount: UInt8
        public let hasDragged: Bool
        public let behavior: SelectionGestureBehavior
        public let autoscroll: SelectionAutoscroll
        public let selectionChanged: Bool

        public init(
            clickCount: UInt8,
            hasDragged: Bool,
            behavior: SelectionGestureBehavior,
            autoscroll: SelectionAutoscroll,
            selectionChanged: Bool
        ) {
            self.clickCount = clickCount
            self.hasDragged = hasDragged
            self.behavior = behavior
            self.autoscroll = autoscroll
            self.selectionChanged = selectionChanged
        }
    }
}
