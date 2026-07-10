extension Terminal {
    /// Values used to answer terminal-originated capability and geometry queries.
    public struct QueryPolicy: Sendable, Equatable {
        public struct Size: Sendable, Equatable {
            public let columns: UInt16
            public let rows: UInt16
            public let cellWidth: UInt32
            public let cellHeight: UInt32

            public init(columns: UInt16, rows: UInt16, cellWidth: UInt32, cellHeight: UInt32) {
                self.columns = columns
                self.rows = rows
                self.cellWidth = cellWidth
                self.cellHeight = cellHeight
            }
        }

        public enum SizeResponse: Sendable, Equatable {
            /// Answers with the dimensions most recently passed to `resize(to:cellWidth:cellHeight:)`.
            case currentTerminal
            case fixed(Size)
        }

        public enum ColorScheme: Sendable, Equatable {
            case light
            case dark
        }

        public struct DeviceAttributes: Sendable, Equatable {
            public struct Primary: Sendable, Equatable {
                public let conformanceLevel: UInt16
                public let featureCodes: [UInt16]

                public init(conformanceLevel: UInt16, featureCodes: [UInt16] = []) {
                    self.conformanceLevel = conformanceLevel
                    self.featureCodes = featureCodes
                }
            }

            public struct Secondary: Sendable, Equatable {
                public let deviceType: UInt16
                public let firmwareVersion: UInt16
                public let romCartridge: UInt16

                public init(deviceType: UInt16, firmwareVersion: UInt16, romCartridge: UInt16 = 0) {
                    self.deviceType = deviceType
                    self.firmwareVersion = firmwareVersion
                    self.romCartridge = romCartridge
                }
            }

            public let primary: Primary
            public let secondary: Secondary
            public let tertiaryUnitID: UInt32

            public init(primary: Primary, secondary: Secondary, tertiaryUnitID: UInt32 = 0) {
                self.primary = primary
                self.secondary = secondary
                self.tertiaryUnitID = tertiaryUnitID
            }
        }

        /// `nil` ignores XTWINOPS size queries.
        public let size: SizeResponse?
        /// `nil` ignores color-scheme queries.
        public let colorScheme: ColorScheme?
        /// `nil` ignores device-attribute queries.
        public let deviceAttributes: DeviceAttributes?

        public init(
            size: SizeResponse? = nil,
            colorScheme: ColorScheme? = nil,
            deviceAttributes: DeviceAttributes? = nil
        ) {
            self.size = size
            self.colorScheme = colorScheme
            self.deviceAttributes = deviceAttributes
        }
    }

    public enum FocusEvent: Sendable, Equatable {
        case gained
        case lost
    }
}
