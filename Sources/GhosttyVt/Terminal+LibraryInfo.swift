import GhosttyVtRaw

extension Terminal {
    /// Returns copied build metadata for the linked libghostty-vt binary.
    public static func libraryInfo() throws -> LibraryInfo {
        var simd = false
        var kittyGraphics = false
        var tmuxControlMode = false
        var optimization: GhosttyOptimizeMode = GHOSTTY_OPTIMIZE_DEBUG
        var major = 0
        var minor = 0
        var patch = 0

        try check(ghostty_build_info(GHOSTTY_BUILD_INFO_SIMD, &simd))
        try check(ghostty_build_info(GHOSTTY_BUILD_INFO_KITTY_GRAPHICS, &kittyGraphics))
        try check(ghostty_build_info(GHOSTTY_BUILD_INFO_TMUX_CONTROL_MODE, &tmuxControlMode))
        try check(ghostty_build_info(GHOSTTY_BUILD_INFO_OPTIMIZE, &optimization))
        try check(ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_MAJOR, &major))
        try check(ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_MINOR, &minor))
        try check(ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_PATCH, &patch))

        let version = try libraryString(GHOSTTY_BUILD_INFO_VERSION_STRING)
        let prerelease = try libraryString(GHOSTTY_BUILD_INFO_VERSION_PRE)
        let buildMetadata = try libraryString(GHOSTTY_BUILD_INFO_VERSION_BUILD)
        return .init(
            isSIMDEnabled: simd,
            supportsKittyGraphics: kittyGraphics,
            supportsTmuxControlMode: tmuxControlMode,
            optimization: libraryOptimization(from: optimization),
            version: version,
            majorVersion: major,
            minorVersion: minor,
            patchVersion: patch,
            prerelease: prerelease.isEmpty ? nil : prerelease,
            buildMetadata: buildMetadata.isEmpty ? nil : buildMetadata
        )
    }

    private static func libraryString(_ data: GhosttyBuildInfo) throws -> String {
        var rawString = GhosttyString()
        try check(ghostty_build_info(data, &rawString))
        guard rawString.len > 0, let pointer = rawString.ptr else { return "" }
        return String(decoding: UnsafeBufferPointer(start: pointer, count: rawString.len), as: UTF8.self)
    }

    private static func libraryOptimization(from raw: GhosttyOptimizeMode) -> LibraryInfo.Optimization {
        switch raw {
        case GHOSTTY_OPTIMIZE_RELEASE_SAFE:
            return .releaseSafe
        case GHOSTTY_OPTIMIZE_RELEASE_SMALL:
            return .releaseSmall
        case GHOSTTY_OPTIMIZE_RELEASE_FAST:
            return .releaseFast
        case GHOSTTY_OPTIMIZE_DEBUG:
            return .debug
        default:
            return .unknown
        }
    }
}
