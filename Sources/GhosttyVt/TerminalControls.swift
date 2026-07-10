import GhosttyVtRaw

extension Terminal {
    public enum ViewportPosition: Sendable, Equatable {
        case top
        case bottom
        /// Negative values move toward scrollback; positive values move toward the active area.
        case delta(Int)
        /// An absolute row offset from the top of the scrollable area.
        case row(Int)
    }

    public struct DefaultTheme: Sendable, Equatable {
        public let foreground: TerminalFrame.RGBColor?
        public let background: TerminalFrame.RGBColor?
        public let cursor: TerminalFrame.RGBColor?
        /// `nil` resets to libghostty-vt's built-in palette.
        public let palette: [TerminalFrame.RGBColor]?

        public init(
            foreground: TerminalFrame.RGBColor? = nil,
            background: TerminalFrame.RGBColor? = nil,
            cursor: TerminalFrame.RGBColor? = nil,
            palette: [TerminalFrame.RGBColor]? = nil
        ) {
            self.foreground = foreground
            self.background = background
            self.cursor = cursor
            self.palette = palette
        }
    }

    public struct KittyKeyboardFlags: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let disambiguateEscapeCodes = Self(rawValue: 1 << 0)
        public static let reportEvents = Self(rawValue: 1 << 1)
        public static let reportAlternateKeys = Self(rawValue: 1 << 2)
        public static let reportAllKeys = Self(rawValue: 1 << 3)
        public static let reportAssociatedText = Self(rawValue: 1 << 4)
    }

    public struct Status: Sendable, Equatable {
        public enum Screen: Sendable, Equatable {
            case primary
            case alternate
        }

        public struct Scrollbar: Sendable, Equatable {
            public let totalRows: UInt64
            public let offset: UInt64
            public let visibleRows: UInt64

            public init(totalRows: UInt64, offset: UInt64, visibleRows: UInt64) {
                self.totalRows = totalRows
                self.offset = offset
                self.visibleRows = visibleRows
            }
        }

        public let activeScreen: Screen
        public let scrollbar: Scrollbar
        public let scrollbackRows: Int
        public let isViewportActive: Bool
        public let isMouseReportingEnabled: Bool
        public let kittyKeyboardFlags: KittyKeyboardFlags
        public let title: String
        public let workingDirectory: String?

        public init(
            activeScreen: Screen,
            scrollbar: Scrollbar,
            scrollbackRows: Int,
            isViewportActive: Bool,
            isMouseReportingEnabled: Bool,
            kittyKeyboardFlags: KittyKeyboardFlags,
            title: String,
            workingDirectory: String?
        ) {
            self.activeScreen = activeScreen
            self.scrollbar = scrollbar
            self.scrollbackRows = scrollbackRows
            self.isViewportActive = isViewportActive
            self.isMouseReportingEnabled = isMouseReportingEnabled
            self.kittyKeyboardFlags = kittyKeyboardFlags
            self.title = title
            self.workingDirectory = workingDirectory
        }
    }
}
