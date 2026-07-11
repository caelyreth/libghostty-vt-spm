import GhosttyVtRaw

extension Terminal {
    /// Immutable capabilities and version data reported by the linked libghostty-vt binary.
    public struct LibraryInfo: Sendable, Equatable {
        public enum Optimization: Sendable, Equatable {
            case debug
            case releaseSafe
            case releaseSmall
            case releaseFast
            case unknown
        }

        public let isSIMDEnabled: Bool
        public let supportsKittyGraphics: Bool
        public let supportsTmuxControlMode: Bool
        public let optimization: Optimization
        public let version: String
        public let majorVersion: Int
        public let minorVersion: Int
        public let patchVersion: Int
        public let prerelease: String?
        public let buildMetadata: String?

        public init(
            isSIMDEnabled: Bool,
            supportsKittyGraphics: Bool,
            supportsTmuxControlMode: Bool,
            optimization: Optimization,
            version: String,
            majorVersion: Int,
            minorVersion: Int,
            patchVersion: Int,
            prerelease: String?,
            buildMetadata: String?
        ) {
            self.isSIMDEnabled = isSIMDEnabled
            self.supportsKittyGraphics = supportsKittyGraphics
            self.supportsTmuxControlMode = supportsTmuxControlMode
            self.optimization = optimization
            self.version = version
            self.majorVersion = majorVersion
            self.minorVersion = minorVersion
            self.patchVersion = patchVersion
            self.prerelease = prerelease
            self.buildMetadata = buildMetadata
        }
    }
}
