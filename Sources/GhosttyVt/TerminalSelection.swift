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
}
