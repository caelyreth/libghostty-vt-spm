/// A Swift-owned incremental render update.
///
/// A full update contains every viewport row. A partial update contains only
/// changed rows. Consumers retain their previously rendered rows and apply
/// partial updates by row index.
public struct TerminalFrame: Sendable, Equatable {
    public enum DirtyState: Sendable, Equatable {
        case clean
        case partial
        case full
    }

    public struct RGBColor: Sendable, Equatable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public enum Color: Sendable, Equatable {
        case palette(UInt8)
        case rgb(RGBColor)
    }

    public enum Underline: Sendable, Equatable {
        case none
        case single
        case double
        case curly
        case dotted
        case dashed
        case unknown(Int32)
    }

    public struct Style: Sendable, Equatable {
        public let foreground: Color?
        public let background: Color?
        public let underlineColor: Color?
        public let isBold: Bool
        public let isItalic: Bool
        public let isFaint: Bool
        public let isBlinking: Bool
        public let isInverse: Bool
        public let isInvisible: Bool
        public let isStrikethrough: Bool
        public let isOverlined: Bool
        public let underline: Underline

        public init(
            foreground: Color?,
            background: Color?,
            underlineColor: Color?,
            isBold: Bool,
            isItalic: Bool,
            isFaint: Bool,
            isBlinking: Bool,
            isInverse: Bool,
            isInvisible: Bool,
            isStrikethrough: Bool,
            isOverlined: Bool,
            underline: Underline
        ) {
            self.foreground = foreground
            self.background = background
            self.underlineColor = underlineColor
            self.isBold = isBold
            self.isItalic = isItalic
            self.isFaint = isFaint
            self.isBlinking = isBlinking
            self.isInverse = isInverse
            self.isInvisible = isInvisible
            self.isStrikethrough = isStrikethrough
            self.isOverlined = isOverlined
            self.underline = underline
        }
    }

    public enum CellWidth: Sendable, Equatable {
        case narrow
        case wide
        case spacerTail
        case spacerHead
    }

    public enum SemanticContent: Sendable, Equatable {
        case output
        case input
        case prompt
    }

    public struct Cell: Sendable, Equatable {
        public let column: UInt16
        public let text: String
        public let width: CellWidth
        public let style: Style
        public let resolvedForeground: RGBColor?
        public let resolvedBackground: RGBColor?
        public let hasHyperlink: Bool
        public let isProtected: Bool
        public let semanticContent: SemanticContent

        public init(
            column: UInt16,
            text: String,
            width: CellWidth,
            style: Style,
            resolvedForeground: RGBColor?,
            resolvedBackground: RGBColor?,
            hasHyperlink: Bool,
            isProtected: Bool,
            semanticContent: SemanticContent
        ) {
            self.column = column
            self.text = text
            self.width = width
            self.style = style
            self.resolvedForeground = resolvedForeground
            self.resolvedBackground = resolvedBackground
            self.hasHyperlink = hasHyperlink
            self.isProtected = isProtected
            self.semanticContent = semanticContent
        }
    }

    public struct Selection: Sendable, Equatable {
        public let startColumn: UInt16
        public let endColumn: UInt16

        public init(startColumn: UInt16, endColumn: UInt16) {
            self.startColumn = startColumn
            self.endColumn = endColumn
        }
    }

    public enum SemanticPrompt: Sendable, Equatable {
        case none
        case primary
        case continuation
    }

    public struct Row: Sendable, Equatable {
        public let index: UInt16
        public let isSoftWrapped: Bool
        public let isContinuation: Bool
        public let semanticPrompt: SemanticPrompt
        public let selection: Selection?
        public let cells: [Cell]

        public init(
            index: UInt16,
            isSoftWrapped: Bool,
            isContinuation: Bool,
            semanticPrompt: SemanticPrompt,
            selection: Selection?,
            cells: [Cell]
        ) {
            self.index = index
            self.isSoftWrapped = isSoftWrapped
            self.isContinuation = isContinuation
            self.semanticPrompt = semanticPrompt
            self.selection = selection
            self.cells = cells
        }
    }

    public struct Theme: Sendable, Equatable {
        public let foreground: RGBColor
        public let background: RGBColor
        public let cursor: RGBColor?
        public let palette: [RGBColor]

        public init(
            foreground: RGBColor,
            background: RGBColor,
            cursor: RGBColor?,
            palette: [RGBColor]
        ) {
            self.foreground = foreground
            self.background = background
            self.cursor = cursor
            self.palette = palette
        }
    }

    public struct Position: Sendable, Equatable {
        public let column: UInt16
        public let row: UInt16

        public init(column: UInt16, row: UInt16) {
            self.column = column
            self.row = row
        }
    }

    public enum CursorStyle: Sendable, Equatable {
        case bar
        case block
        case underline
        case hollowBlock
    }

    public struct Cursor: Sendable, Equatable {
        public let isVisible: Bool
        public let isBlinking: Bool
        public let isPasswordInput: Bool
        public let isWideTail: Bool
        public let style: CursorStyle
        public let position: Position?

        public init(
            isVisible: Bool,
            isBlinking: Bool,
            isPasswordInput: Bool,
            isWideTail: Bool,
            style: CursorStyle,
            position: Position?
        ) {
            self.isVisible = isVisible
            self.isBlinking = isBlinking
            self.isPasswordInput = isPasswordInput
            self.isWideTail = isWideTail
            self.style = style
            self.position = position
        }
    }

    public let size: Terminal.Size
    public let dirtyState: DirtyState
    public let theme: Theme
    public let cursor: Cursor
    public let rows: [Row]

    public init(
        size: Terminal.Size,
        dirtyState: DirtyState,
        theme: Theme,
        cursor: Cursor,
        rows: [Row]
    ) {
        self.size = size
        self.dirtyState = dirtyState
        self.theme = theme
        self.cursor = cursor
        self.rows = rows
    }
}
