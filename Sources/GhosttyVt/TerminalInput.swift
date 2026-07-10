import Foundation

extension Terminal {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let shift = Self(rawValue: 1 << 0)
        public static let control = Self(rawValue: 1 << 1)
        public static let option = Self(rawValue: 1 << 2)
        public static let command = Self(rawValue: 1 << 3)
        public static let capsLock = Self(rawValue: 1 << 4)
        public static let numLock = Self(rawValue: 1 << 5)
        public static let rightShift = Self(rawValue: 1 << 6)
        public static let rightControl = Self(rawValue: 1 << 7)
        public static let rightOption = Self(rawValue: 1 << 8)
        public static let rightCommand = Self(rawValue: 1 << 9)
    }

    public struct KeyEvent: Sendable, Equatable {
        public enum Action: Sendable, Equatable {
            case press
            case release
            case repeatPress
        }

        public enum Key: Sendable, Equatable {
            /// Layout-dependent text supplied through `text`.
            case text
            case backspace
            case tab
            case enter
            case escape
            case space
            case arrowUp
            case arrowDown
            case arrowLeft
            case arrowRight
            case home
            case end
            case pageUp
            case pageDown
            case insert
            case delete
            case function(UInt8)
        }

        public let key: Key
        public let text: String?
        public let action: Action
        public let modifiers: Modifiers
        public let consumedModifiers: Modifiers
        public let isComposing: Bool
        public let unshiftedCodepoint: UInt32?

        public init(
            key: Key,
            text: String? = nil,
            action: Action = .press,
            modifiers: Modifiers = [],
            consumedModifiers: Modifiers = [],
            isComposing: Bool = false,
            unshiftedCodepoint: UInt32? = nil
        ) {
            self.key = key
            self.text = text
            self.action = action
            self.modifiers = modifiers
            self.consumedModifiers = consumedModifiers
            self.isComposing = isComposing
            self.unshiftedCodepoint = unshiftedCodepoint
        }

        public init(
            text: String,
            action: Action = .press,
            modifiers: Modifiers = [],
            consumedModifiers: Modifiers = [],
            isComposing: Bool = false,
            unshiftedCodepoint: UInt32? = nil
        ) {
            self.init(
                key: .text,
                text: text,
                action: action,
                modifiers: modifiers,
                consumedModifiers: consumedModifiers,
                isComposing: isComposing,
                unshiftedCodepoint: unshiftedCodepoint
            )
        }
    }

    public struct MouseEvent: Sendable, Equatable {
        public enum Action: Sendable, Equatable {
            case press
            case release
            case motion
        }

        public enum Button: Sendable, Equatable, Hashable {
            case left
            case right
            case middle
            case other(UInt8)

            public static let scrollUp = Self.other(4)
            public static let scrollDown = Self.other(5)
            public static let scrollLeft = Self.other(6)
            public static let scrollRight = Self.other(7)
        }

        public struct Position: Sendable, Equatable {
            public let x: Float
            public let y: Float

            public init(x: Float, y: Float) {
                self.x = x
                self.y = y
            }
        }

        public let action: Action
        public let button: Button?
        public let modifiers: Modifiers
        public let position: Position

        public init(
            action: Action,
            button: Button? = nil,
            modifiers: Modifiers = [],
            position: Position
        ) {
            self.action = action
            self.button = button
            self.modifiers = modifiers
            self.position = position
        }
    }

    public struct MouseGeometry: Sendable, Equatable {
        public let screenWidth: UInt32
        public let screenHeight: UInt32
        public let cellWidth: UInt32
        public let cellHeight: UInt32
        public let paddingTop: UInt32
        public let paddingBottom: UInt32
        public let paddingRight: UInt32
        public let paddingLeft: UInt32

        public init(
            screenWidth: UInt32,
            screenHeight: UInt32,
            cellWidth: UInt32,
            cellHeight: UInt32,
            paddingTop: UInt32 = 0,
            paddingBottom: UInt32 = 0,
            paddingRight: UInt32 = 0,
            paddingLeft: UInt32 = 0
        ) {
            self.screenWidth = screenWidth
            self.screenHeight = screenHeight
            self.cellWidth = cellWidth
            self.cellHeight = cellHeight
            self.paddingTop = paddingTop
            self.paddingBottom = paddingBottom
            self.paddingRight = paddingRight
            self.paddingLeft = paddingLeft
        }
    }
}
