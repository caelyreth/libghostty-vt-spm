import Foundation
import GhosttyVtRaw

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
        /// Bytes returned for ENQ. `nil` sends no response.
        public let enquiryResponse: Data?
        /// Value returned for XTVERSION. `nil` keeps libghostty-vt's default response.
        public let xtermVersion: String?

        public init(
            size: SizeResponse? = nil,
            colorScheme: ColorScheme? = nil,
            deviceAttributes: DeviceAttributes? = nil,
            enquiryResponse: Data? = nil,
            xtermVersion: String? = nil
        ) {
            self.size = size
            self.colorScheme = colorScheme
            self.deviceAttributes = deviceAttributes
            self.enquiryResponse = enquiryResponse
            self.xtermVersion = xtermVersion
        }
    }

    public enum FocusEvent: Sendable, Equatable {
        case gained
        case lost
    }
}

final class TerminalQueryStringStorage {
    private let pointer: UnsafeMutablePointer<UInt8>?
    private let count: Int

    init(bytes: [UInt8] = []) {
        count = bytes.count
        guard !bytes.isEmpty else {
            pointer = nil
            return
        }

        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
        storage.initialize(from: bytes, count: bytes.count)
        pointer = storage
    }

    deinit {
        pointer?.deinitialize(count: count)
        pointer?.deallocate()
    }

    var string: GhosttyString {
        .init(ptr: pointer.map { UnsafePointer($0) }, len: count)
    }
}
