extension Terminal {
    public enum ExportFormat: Sendable, Equatable {
        case plain
        case terminal
        case html
    }

    /// Controls formatting of a screen or selection export.
    public struct ExportOptions: Sendable, Equatable {
        public let format: ExportFormat
        public let unwrapSoftLines: Bool
        public let trimTrailingWhitespace: Bool

        public init(
            format: ExportFormat = .plain,
            unwrapSoftLines: Bool = true,
            trimTrailingWhitespace: Bool = true
        ) {
            self.format = format
            self.unwrapSoftLines = unwrapSoftLines
            self.trimTrailingWhitespace = trimTrailingWhitespace
        }
    }
}
