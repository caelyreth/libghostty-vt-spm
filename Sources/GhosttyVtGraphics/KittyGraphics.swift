import Foundation
@_spi(GhosttyVtGraphics) import GhosttyVt
import GhosttyVtRaw

/// Swift-owned inspection and configuration for Kitty graphics protocol data.
public enum KittyGraphics {
    /// Decoded RGBA pixels returned by a host-provided PNG decoder.
    public struct PNGImage: Sendable, Equatable {
        public let width: UInt32
        public let height: UInt32
        public let pixels: Data

        public init(width: UInt32, height: UInt32, pixels: Data) throws {
            guard width > 0, height > 0 else {
                throw Error.invalidPNGImage
            }
            let bytesPerRow = Int(width).multipliedReportingOverflow(by: 4)
            let byteCount = bytesPerRow.partialValue.multipliedReportingOverflow(by: Int(height))
            guard !bytesPerRow.overflow, !byteCount.overflow, pixels.count == byteCount.partialValue else {
                throw Error.invalidPNGImage
            }
            self.width = width
            self.height = height
            self.pixels = pixels
        }
    }

    /// The process-wide callback used when libghostty-vt receives PNG graphics data.
    public typealias PNGDecoder = @Sendable (Data) -> PNGImage?

    public enum Error: Swift.Error, Sendable, Equatable {
        case invalidPNGImage
        case pngDecoderAlreadyInstalled
    }

    /// Installs the process-wide PNG decoder before terminals receive Kitty graphics data.
    ///
    /// The decoder must be safe to call concurrently. It receives copied PNG bytes and
    /// returns straight RGBA pixels; the wrapper transfers those pixels into Ghostty's
    /// allocator as required by the C API.
    public static func installPNGDecoder(_ decoder: @escaping PNGDecoder) throws {
        decoderBox.lock.lock()
        defer { decoderBox.lock.unlock() }
        guard decoderBox.decoder == nil else {
            throw Error.pngDecoderAlreadyInstalled
        }

        let callback = unsafeBitCast(pngDecoderCallback, to: UnsafeRawPointer.self)
        try checkKittyGraphicsResult(ghostty_sys_set(GHOSTTY_SYS_OPT_DECODE_PNG, callback))
        decoderBox.decoder = decoder
    }

    private final class DecoderBox: @unchecked Sendable {
        let lock = NSLock()
        var decoder: PNGDecoder?
    }

    private static let decoderBox = DecoderBox()

    private static let pngDecoderCallback: @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<GhosttyAllocator>?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<GhosttySysImage>?
    ) -> Bool = { _, allocator, source, count, output in
        guard count > 0, let source, let output else { return false }

        decoderBox.lock.lock()
        let decoder = decoderBox.decoder
        decoderBox.lock.unlock()
        guard let image = decoder?(Data(bytes: source, count: count)) else { return false }
        guard let destination = ghostty_alloc(allocator, image.pixels.count) else { return false }

        image.pixels.withUnsafeBytes { pixels in
            destination.initialize(from: pixels.bindMemory(to: UInt8.self).baseAddress!, count: pixels.count)
        }
        output.pointee.width = image.width
        output.pointee.height = image.height
        output.pointee.data = destination
        output.pointee.data_len = image.pixels.count
        return true
    }
}

extension Terminal {
    /// Configures Kitty graphics storage and the enabled transport media.
    ///
    /// A zero storage limit disables graphics and deletes stored images. File, temporary
    /// file, and shared-memory media remain opt-in because they cross the terminal's
    /// normal byte-stream boundary.
    public func configureKittyGraphics(_ configuration: KittyGraphicsConfiguration) throws -> Bool {
        try withTerminalHandle { handle in
            var allowsFile = configuration.allowsFileMedium
            var allowsTemporaryFile = configuration.allowsTemporaryFileMedium
            var allowsSharedMemory = configuration.allowsSharedMemoryMedium
            var storageLimit = configuration.storageLimitBytes

            try checkKittyGraphicsResult(
                ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_FILE, &allowsFile)
            )
            try checkKittyGraphicsResult(
                ghostty_terminal_set(
                    handle,
                    GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_TEMP_FILE,
                    &allowsTemporaryFile
                )
            )
            try checkKittyGraphicsResult(
                ghostty_terminal_set(
                    handle,
                    GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_SHARED_MEM,
                    &allowsSharedMemory
                )
            )
            try checkKittyGraphicsResult(
                ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT, &storageLimit)
            )
            return try kittyGraphicsConfigurationLocked(handle) != nil
        }
    }

    /// Returns the active Kitty graphics configuration, or `nil` when graphics are unavailable.
    public func kittyGraphicsConfiguration() throws -> KittyGraphicsConfiguration? {
        try withTerminalHandle { handle in
            try kittyGraphicsConfigurationLocked(handle)
        }
    }

    /// Copies image metadata, optional pixels, and current placement geometry for rendering.
    ///
    /// The returned data has no borrowed relationship with the terminal. Cache image pixels by
    /// `KittyGraphicsImage.generation`; placement geometry may change when the viewport moves
    /// even when the storage generation does not.
    public func kittyGraphicsSnapshot(
        options: KittyGraphicsSnapshotOptions = .init()
    ) throws -> KittyGraphicsSnapshot? {
        try withTerminalHandle { handle in
            var graphics: OpaquePointer?
            let graphicsResult = ghostty_terminal_get(
                handle,
                GHOSTTY_TERMINAL_DATA_KITTY_GRAPHICS,
                &graphics
            )
            if graphicsResult == GHOSTTY_NO_VALUE {
                return nil
            }
            try checkKittyGraphicsResult(graphicsResult)
            guard let graphics else {
                throw TerminalError.unexpectedResult
            }

            var generation: UInt64 = 0
            try checkKittyGraphicsResult(
                ghostty_kitty_graphics_get(graphics, GHOSTTY_KITTY_GRAPHICS_DATA_GENERATION, &generation)
            )

            var rawIterator: OpaquePointer?
            try checkKittyGraphicsResult(ghostty_kitty_graphics_placement_iterator_new(nil, &rawIterator))
            defer { ghostty_kitty_graphics_placement_iterator_free(rawIterator) }
            guard let iterator = rawIterator else {
                throw TerminalError.unexpectedResult
            }

            try checkKittyGraphicsResult(
                ghostty_kitty_graphics_get(
                    graphics,
                    GHOSTTY_KITTY_GRAPHICS_DATA_PLACEMENT_ITERATOR,
                    &rawIterator
                )
            )
            var layer = rawLayer(options.layer)
            try checkKittyGraphicsResult(
                ghostty_kitty_graphics_placement_iterator_set(
                    iterator,
                    GHOSTTY_KITTY_GRAPHICS_PLACEMENT_ITERATOR_OPTION_LAYER,
                    &layer
                )
            )

            var images: [UInt32: KittyGraphicsImage] = [:]
            var placements: [KittyGraphicsPlacement] = []
            while ghostty_kitty_graphics_placement_next(iterator) {
                var imageIdentifier: UInt32 = 0
                var placementIdentifier: UInt32 = 0
                var isVirtual = false
                var xOffset: UInt32 = 0
                var yOffset: UInt32 = 0
                var zIndex: Int32 = 0
                let placementKeys: [GhosttyKittyGraphicsPlacementData] = [
                    GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IMAGE_ID,
                    GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_PLACEMENT_ID,
                    GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IS_VIRTUAL,
                    GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_X_OFFSET,
                    GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Y_OFFSET,
                    GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Z,
                ]
                try checkKittyGraphicsResult(
                    placementKeys.withUnsafeBufferPointer { keys in
                        KittyGraphicsOutputPointers.withPointers(
                            &imageIdentifier,
                            &placementIdentifier,
                            &isVirtual,
                            &xOffset,
                            &yOffset,
                            &zIndex
                        ) { values in
                            ghostty_kitty_graphics_placement_get_multi(
                                iterator,
                                keys.count,
                                keys.baseAddress,
                                values.baseAddress,
                                nil
                            )
                        }
                    )
                )
                guard let image = ghostty_kitty_graphics_image(graphics, imageIdentifier) else {
                    throw TerminalError.unexpectedResult
                }

                if images[imageIdentifier] == nil {
                    images[imageIdentifier] = try kittyGraphicsImage(
                        image,
                        includePixels: options.includesPixels
                    )
                }

                var renderInfo = GhosttyKittyGraphicsPlacementRenderInfo()
                renderInfo.size = MemoryLayout<GhosttyKittyGraphicsPlacementRenderInfo>.size
                try checkKittyGraphicsResult(
                    ghostty_kitty_graphics_placement_render_info(iterator, image, handle, &renderInfo)
                )
                let gridBounds = try kittyGraphicsPlacementBounds(iterator, image: image, terminal: handle)
                placements.append(
                    .init(
                        imageIdentifier: imageIdentifier,
                        placementIdentifier: placementIdentifier,
                        isVirtual: isVirtual,
                        xOffset: xOffset,
                        yOffset: yOffset,
                        zIndex: zIndex,
                        renderInfo: .init(raw: renderInfo),
                        gridBounds: gridBounds
                    )
                )
            }

            return .init(
                generation: generation,
                images: images.values.sorted { $0.identifier < $1.identifier },
                placements: placements
            )
        }
    }

    private func kittyGraphicsConfigurationLocked(
        _ handle: OpaquePointer
    ) throws -> KittyGraphicsConfiguration? {
        var storageLimit: UInt64 = 0
        let storageResult = ghostty_terminal_get(
            handle,
            GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_STORAGE_LIMIT,
            &storageLimit
        )
        if storageResult == GHOSTTY_NO_VALUE {
            return nil
        }
        try checkKittyGraphicsResult(storageResult)

        var allowsFile = false
        var allowsTemporaryFile = false
        var allowsSharedMemory = false
        try checkKittyGraphicsResult(
            ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_FILE, &allowsFile)
        )
        try checkKittyGraphicsResult(
            ghostty_terminal_get(
                handle,
                GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_TEMP_FILE,
                &allowsTemporaryFile
            )
        )
        try checkKittyGraphicsResult(
            ghostty_terminal_get(
                handle,
                GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_SHARED_MEM,
                &allowsSharedMemory
            )
        )
        return .init(
            storageLimitBytes: storageLimit,
            allowsFileMedium: allowsFile,
            allowsTemporaryFileMedium: allowsTemporaryFile,
            allowsSharedMemoryMedium: allowsSharedMemory
        )
    }

    private func kittyGraphicsImage(
        _ image: OpaquePointer,
        includePixels: Bool
    ) throws -> KittyGraphicsImage {
        var identifier: UInt32 = 0
        var number: UInt32 = 0
        var width: UInt32 = 0
        var height: UInt32 = 0
        var format: GhosttyKittyImageFormat = GHOSTTY_KITTY_IMAGE_FORMAT_RGBA
        var generation: UInt64 = 0
        let imageKeys: [GhosttyKittyGraphicsImageData] = [
            GHOSTTY_KITTY_IMAGE_DATA_ID,
            GHOSTTY_KITTY_IMAGE_DATA_NUMBER,
            GHOSTTY_KITTY_IMAGE_DATA_WIDTH,
            GHOSTTY_KITTY_IMAGE_DATA_HEIGHT,
            GHOSTTY_KITTY_IMAGE_DATA_FORMAT,
            GHOSTTY_KITTY_IMAGE_DATA_GENERATION,
        ]
        try checkKittyGraphicsResult(
            imageKeys.withUnsafeBufferPointer { keys in
                KittyGraphicsOutputPointers.withPointers(
                    &identifier,
                    &number,
                    &width,
                    &height,
                    &format,
                    &generation
                ) { values in
                    ghostty_kitty_graphics_image_get_multi(
                        image,
                        keys.count,
                        keys.baseAddress,
                        values.baseAddress,
                        nil
                    )
                }
            }
        )

        let pixels: Data?
        if includePixels {
            var pointer: UnsafePointer<UInt8>?
            var count = 0
            try checkKittyGraphicsResult(
                ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_DATA_PTR, &pointer)
            )
            try checkKittyGraphicsResult(
                ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_DATA_LEN, &count)
            )
            guard count >= 0, let pointer else {
                throw TerminalError.unexpectedResult
            }
            pixels = Data(bytes: pointer, count: count)
        } else {
            pixels = nil
        }
        return .init(
            identifier: identifier,
            number: number,
            width: width,
            height: height,
            format: .init(raw: format),
            generation: generation,
            pixels: pixels
        )
    }

    private func kittyGraphicsPlacementBounds(
        _ iterator: OpaquePointer,
        image: OpaquePointer,
        terminal: OpaquePointer
    ) throws -> GridRange? {
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        let result = ghostty_kitty_graphics_placement_rect(iterator, image, terminal, &selection)
        if result == GHOSTTY_NO_VALUE {
            return nil
        }
        try checkKittyGraphicsResult(result)
        guard let start = try kittyGraphicsGridPoint(from: &selection.start, terminal: terminal),
              let end = try kittyGraphicsGridPoint(from: &selection.end, terminal: terminal) else {
            throw TerminalError.unexpectedResult
        }
        return .init(start: start, end: end, isRectangular: selection.rectangle)
    }

    private func kittyGraphicsGridPoint(
        from reference: inout GhosttyGridRef,
        terminal: OpaquePointer
    ) throws -> GridPoint? {
        var coordinate = GhosttyPointCoordinate()
        let result = ghostty_terminal_point_from_grid_ref(
            terminal,
            &reference,
            GHOSTTY_POINT_TAG_SCREEN,
            &coordinate
        )
        if result == GHOSTTY_NO_VALUE {
            return nil
        }
        try checkKittyGraphicsResult(result)
        return .init(column: coordinate.x, row: coordinate.y, coordinateSpace: .screen)
    }
}

public struct KittyGraphicsConfiguration: Sendable, Equatable {
    public let storageLimitBytes: UInt64
    public let allowsFileMedium: Bool
    public let allowsTemporaryFileMedium: Bool
    public let allowsSharedMemoryMedium: Bool

    public init(
        storageLimitBytes: UInt64 = 64 * 1024 * 1024,
        allowsFileMedium: Bool = false,
        allowsTemporaryFileMedium: Bool = false,
        allowsSharedMemoryMedium: Bool = false
    ) {
        self.storageLimitBytes = storageLimitBytes
        self.allowsFileMedium = allowsFileMedium
        self.allowsTemporaryFileMedium = allowsTemporaryFileMedium
        self.allowsSharedMemoryMedium = allowsSharedMemoryMedium
    }
}

public enum KittyGraphicsLayer: Sendable, Equatable {
    case all
    case belowBackground
    case belowText
    case aboveText
}

public struct KittyGraphicsSnapshotOptions: Sendable, Equatable {
    public let layer: KittyGraphicsLayer
    public let includesPixels: Bool

    public init(layer: KittyGraphicsLayer = .all, includesPixels: Bool = true) {
        self.layer = layer
        self.includesPixels = includesPixels
    }
}

public struct KittyGraphicsSnapshot: Sendable, Equatable {
    public let generation: UInt64
    public let images: [KittyGraphicsImage]
    public let placements: [KittyGraphicsPlacement]

    public init(generation: UInt64, images: [KittyGraphicsImage], placements: [KittyGraphicsPlacement]) {
        self.generation = generation
        self.images = images
        self.placements = placements
    }
}

public struct KittyGraphicsImage: Sendable, Equatable {
    public enum Format: Sendable, Equatable {
        case rgb
        case rgba
        case grayscaleAlpha
        case grayscale
        case unknown

        fileprivate init(raw: GhosttyKittyImageFormat) {
            switch raw {
            case GHOSTTY_KITTY_IMAGE_FORMAT_RGB:
                self = .rgb
            case GHOSTTY_KITTY_IMAGE_FORMAT_RGBA:
                self = .rgba
            case GHOSTTY_KITTY_IMAGE_FORMAT_GRAY_ALPHA:
                self = .grayscaleAlpha
            case GHOSTTY_KITTY_IMAGE_FORMAT_GRAY:
                self = .grayscale
            default:
                self = .unknown
            }
        }
    }

    public let identifier: UInt32
    public let number: UInt32
    public let width: UInt32
    public let height: UInt32
    public let format: Format
    public let generation: UInt64
    /// `nil` when the snapshot requested metadata only.
    public let pixels: Data?

    public init(
        identifier: UInt32,
        number: UInt32,
        width: UInt32,
        height: UInt32,
        format: Format,
        generation: UInt64,
        pixels: Data?
    ) {
        self.identifier = identifier
        self.number = number
        self.width = width
        self.height = height
        self.format = format
        self.generation = generation
        self.pixels = pixels
    }
}

public struct KittyGraphicsPlacement: Sendable, Equatable {
    public struct RenderInfo: Sendable, Equatable {
        public let pixelWidth: UInt32
        public let pixelHeight: UInt32
        public let gridColumns: UInt32
        public let gridRows: UInt32
        public let viewportColumn: Int32
        public let viewportRow: Int32
        public let isViewportVisible: Bool
        public let sourceX: UInt32
        public let sourceY: UInt32
        public let sourceWidth: UInt32
        public let sourceHeight: UInt32

        public init(
            pixelWidth: UInt32,
            pixelHeight: UInt32,
            gridColumns: UInt32,
            gridRows: UInt32,
            viewportColumn: Int32,
            viewportRow: Int32,
            isViewportVisible: Bool,
            sourceX: UInt32,
            sourceY: UInt32,
            sourceWidth: UInt32,
            sourceHeight: UInt32
        ) {
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.gridColumns = gridColumns
            self.gridRows = gridRows
            self.viewportColumn = viewportColumn
            self.viewportRow = viewportRow
            self.isViewportVisible = isViewportVisible
            self.sourceX = sourceX
            self.sourceY = sourceY
            self.sourceWidth = sourceWidth
            self.sourceHeight = sourceHeight
        }

        fileprivate init(raw: GhosttyKittyGraphicsPlacementRenderInfo) {
            pixelWidth = raw.pixel_width
            pixelHeight = raw.pixel_height
            gridColumns = raw.grid_cols
            gridRows = raw.grid_rows
            viewportColumn = raw.viewport_col
            viewportRow = raw.viewport_row
            isViewportVisible = raw.viewport_visible
            sourceX = raw.source_x
            sourceY = raw.source_y
            sourceWidth = raw.source_width
            sourceHeight = raw.source_height
        }
    }

    public let imageIdentifier: UInt32
    public let placementIdentifier: UInt32
    public let isVirtual: Bool
    public let xOffset: UInt32
    public let yOffset: UInt32
    public let zIndex: Int32
    public let renderInfo: RenderInfo
    /// The placement's grid rectangle, or `nil` for virtual placements.
    public let gridBounds: Terminal.GridRange?

    public init(
        imageIdentifier: UInt32,
        placementIdentifier: UInt32,
        isVirtual: Bool,
        xOffset: UInt32,
        yOffset: UInt32,
        zIndex: Int32,
        renderInfo: RenderInfo,
        gridBounds: Terminal.GridRange?
    ) {
        self.imageIdentifier = imageIdentifier
        self.placementIdentifier = placementIdentifier
        self.isVirtual = isVirtual
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.zIndex = zIndex
        self.renderInfo = renderInfo
        self.gridBounds = gridBounds
    }
}

private func rawLayer(_ layer: KittyGraphicsLayer) -> GhosttyKittyPlacementLayer {
    switch layer {
    case .all:
        return GHOSTTY_KITTY_PLACEMENT_LAYER_ALL
    case .belowBackground:
        return GHOSTTY_KITTY_PLACEMENT_LAYER_BELOW_BG
    case .belowText:
        return GHOSTTY_KITTY_PLACEMENT_LAYER_BELOW_TEXT
    case .aboveText:
        return GHOSTTY_KITTY_PLACEMENT_LAYER_ABOVE_TEXT
    }
}

private func checkKittyGraphicsResult(_ result: GhosttyResult) throws {
    switch result {
    case GHOSTTY_SUCCESS:
        return
    case GHOSTTY_OUT_OF_MEMORY:
        throw TerminalError.outOfMemory
    case GHOSTTY_INVALID_VALUE:
        throw TerminalError.invalidValue
    case GHOSTTY_OUT_OF_SPACE:
        throw TerminalError.outOfSpace
    case GHOSTTY_NO_VALUE:
        throw TerminalError.noValue
    default:
        throw TerminalError.unexpectedResult
    }
}

private enum KittyGraphicsOutputPointers {
    static func withPointers<First, Second, Third, Fourth, Fifth, Sixth, Result>(
        _ first: inout First,
        _ second: inout Second,
        _ third: inout Third,
        _ fourth: inout Fourth,
        _ fifth: inout Fifth,
        _ sixth: inout Sixth,
        _ body: (UnsafeMutableBufferPointer<UnsafeMutableRawPointer?>) -> Result
    ) -> Result {
        withUnsafeMutablePointer(to: &first) { firstPointer in
            withUnsafeMutablePointer(to: &second) { secondPointer in
                withUnsafeMutablePointer(to: &third) { thirdPointer in
                    withUnsafeMutablePointer(to: &fourth) { fourthPointer in
                        withUnsafeMutablePointer(to: &fifth) { fifthPointer in
                            withUnsafeMutablePointer(to: &sixth) { sixthPointer in
                                withUnsafeTemporaryAllocation(
                                    of: UnsafeMutableRawPointer?.self,
                                    capacity: 6
                                ) { pointers in
                                    let baseAddress = pointers.baseAddress!
                                    baseAddress.initialize(repeating: nil, count: 6)
                                    defer { baseAddress.deinitialize(count: 6) }
                                    pointers[0] = UnsafeMutableRawPointer(firstPointer)
                                    pointers[1] = UnsafeMutableRawPointer(secondPointer)
                                    pointers[2] = UnsafeMutableRawPointer(thirdPointer)
                                    pointers[3] = UnsafeMutableRawPointer(fourthPointer)
                                    pointers[4] = UnsafeMutableRawPointer(fifthPointer)
                                    pointers[5] = UnsafeMutableRawPointer(sixthPointer)
                                    return body(pointers)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
