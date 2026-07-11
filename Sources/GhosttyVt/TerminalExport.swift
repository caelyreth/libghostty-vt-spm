extension Terminal {
    public enum ExportFormat: Sendable, Equatable {
        case plain
        case terminal
        case html
    }

    /// Controls formatting of a screen or selection export.
    public struct ExportOptions: Sendable, Equatable {
        public struct TerminalState: Sendable, Equatable {
            public struct ScreenState: Sendable, Equatable {
                public let cursor: Bool
                public let style: Bool
                public let hyperlink: Bool
                public let protection: Bool
                public let kittyKeyboard: Bool
                public let characterSets: Bool

                public init(
                    cursor: Bool = false,
                    style: Bool = false,
                    hyperlink: Bool = false,
                    protection: Bool = false,
                    kittyKeyboard: Bool = false,
                    characterSets: Bool = false
                ) {
                    self.cursor = cursor
                    self.style = style
                    self.hyperlink = hyperlink
                    self.protection = protection
                    self.kittyKeyboard = kittyKeyboard
                    self.characterSets = characterSets
                }
            }

            public let palette: Bool
            public let modes: Bool
            public let scrollingRegion: Bool
            public let tabStops: Bool
            public let workingDirectory: Bool
            public let keyboard: Bool
            public let screen: ScreenState

            public init(
                palette: Bool = false,
                modes: Bool = false,
                scrollingRegion: Bool = false,
                tabStops: Bool = false,
                workingDirectory: Bool = false,
                keyboard: Bool = false,
                screen: ScreenState = .init()
            ) {
                self.palette = palette
                self.modes = modes
                self.scrollingRegion = scrollingRegion
                self.tabStops = tabStops
                self.workingDirectory = workingDirectory
                self.keyboard = keyboard
                self.screen = screen
            }
        }

        public let format: ExportFormat
        public let unwrapSoftLines: Bool
        public let trimTrailingWhitespace: Bool
        /// Additional terminal state emitted by terminal-format output.
        public let terminalState: TerminalState

        public init(
            format: ExportFormat = .plain,
            unwrapSoftLines: Bool = true,
            trimTrailingWhitespace: Bool = true,
            terminalState: TerminalState = .init()
        ) {
            self.format = format
            self.unwrapSoftLines = unwrapSoftLines
            self.trimTrailingWhitespace = trimTrailingWhitespace
            self.terminalState = terminalState
        }
    }
}
