import Foundation
import GhosttyVtRaw

extension Terminal {
    /// Encodes a focus transition for forwarding to the pty.
    public static func encodeFocus(_ event: FocusEvent) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 8)
        var written = 0
        var result = buffer.withUnsafeMutableBytes { bytes in
            ghostty_focus_encode(
                focusEvent(from: event),
                bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                bytes.count,
                &written
            )
        }

        if result == GHOSTTY_OUT_OF_SPACE {
            guard written > buffer.count else {
                throw TerminalError.unexpectedResult
            }
            buffer = [UInt8](repeating: 0, count: written)
            written = 0
            result = buffer.withUnsafeMutableBytes { bytes in
                ghostty_focus_encode(
                    focusEvent(from: event),
                    bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                    bytes.count,
                    &written
                )
            }
        }

        try check(result)
        guard written <= buffer.count else {
            throw TerminalError.unexpectedResult
        }
        return Data(buffer.prefix(written))
    }

    /// Updates how libghostty-vt answers terminal-originated queries.
    public func setQueryPolicy(_ policy: QueryPolicy) throws {
        if case .fixed(let size)? = policy.size, size.columns == 0 || size.rows == 0 {
            throw TerminalError.invalidQuerySize
        }
        if let attributes = policy.deviceAttributes, attributes.primary.featureCodes.count > 64 {
            throw TerminalError.invalidDeviceAttributes
        }

        withTerminalLock {
            queryPolicy = policy
        }
    }

    static func focusEvent(from event: FocusEvent) -> GhosttyFocusEvent {
        switch event {
        case .gained:
            return GHOSTTY_FOCUS_GAINED
        case .lost:
            return GHOSTTY_FOCUS_LOST
        }
    }

    static func colorScheme(from scheme: QueryPolicy.ColorScheme) -> GhosttyColorScheme {
        switch scheme {
        case .light:
            return GHOSTTY_COLOR_SCHEME_LIGHT
        case .dark:
            return GHOSTTY_COLOR_SCHEME_DARK
        }
    }

    func sizeReport(for response: QueryPolicy.SizeResponse) -> GhosttySizeReportSize {
        let size: QueryPolicy.Size
        switch response {
        case .currentTerminal:
            size = currentSizeReport
        case .fixed(let fixedSize):
            size = fixedSize
        }

        var rawSize = GhosttySizeReportSize()
        rawSize.rows = size.rows
        rawSize.columns = size.columns
        rawSize.cell_width = size.cellWidth
        rawSize.cell_height = size.cellHeight
        return rawSize
    }

    static func deviceAttributes(from attributes: QueryPolicy.DeviceAttributes) -> GhosttyDeviceAttributes {
        var rawAttributes = GhosttyDeviceAttributes()
        var primary = rawAttributes.primary
        primary.conformance_level = attributes.primary.conformanceLevel
        primary.num_features = attributes.primary.featureCodes.count
        withUnsafeMutableBytes(of: &primary.features) { bytes in
            let features = bytes.bindMemory(to: UInt16.self)
            for (index, feature) in attributes.primary.featureCodes.enumerated() {
                features[index] = feature
            }
        }
        rawAttributes.primary = primary
        rawAttributes.secondary.device_type = attributes.secondary.deviceType
        rawAttributes.secondary.firmware_version = attributes.secondary.firmwareVersion
        rawAttributes.secondary.rom_cartridge = attributes.secondary.romCartridge
        rawAttributes.tertiary.unit_id = attributes.tertiaryUnitID
        return rawAttributes
    }
}
