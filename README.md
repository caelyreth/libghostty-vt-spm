### Ghostty VT Swift Package

Swift Package wrapper for upstream [`libghostty-vt`](https://github.com/ghostty-org/ghostty).

### Terminal Engine

Add this package in SwiftPM and import the Swift-native module:

```swift
import GhosttyVt

let terminal = try Terminal(
    configuration: .init(columns: 80, rows: 24)
)
terminal.feed("Hello, world!\\r\\n")

let frame = try terminal.update()
for row in frame.rows {
    for cell in row.cells {
        // Apply each cell's text, style, width, and metadata to your renderer.
    }
}
```

`GhosttyVt` owns libghostty-vt handles and returns Swift-owned incremental
frames. A full frame contains every viewport row; a partial frame contains
only changed rows, which the renderer applies by row index. It does not export
C functions, pointers, or C structs. `Terminal` is thread-safe and `Sendable`.

The host owns the surrounding terminal application:

- Feed process output with `feed(_:)`.
- Write `Terminal.Event.writeToPty` data from `drainEvents()` back to the PTY.
- Encode host key, mouse, paste, and focus input before writing it to the PTY.
- Render Swift-owned frames, or use the scoped render transaction below.

The package deliberately does not own a process or PTY, rendering backend,
font shaping, clipboard UI, IME, accessibility, persistence, or search UI.

### Rendering

`update()` is the general rendering path. It copies changed rows into a
`TerminalFrame`, so the frame can outlive the call and move freely between the
host's rendering and UI work.

For a renderer that consumes cells immediately, `withRenderTransaction(_:)`
avoids building a frame and exposes rows and cells only for the callback's
duration. Its text callbacks use reusable wrapper-owned buffers. Do not call
back into `Terminal` from inside that transaction.

```swift
try terminal.withRenderTransaction { transaction in
    try transaction.forEachRow { row in
        try row.forEachCell { cell in
            try cell.withUTF8 { bytes in
                renderer.draw(bytes, at: cell.column, style: cell.style)
            }
        }
    }
}
```

### Interaction And Export

Selection uses viewport cells and libghostty-vt's word, line, semantic-output,
and formatting rules. `makeSelectionGesture()` supplies the C-backed
press/drag/release state machine for a host pointer stream, including repeated
clicks and autoscroll. `copySelection()` supplies clipboard-ready text;
`exportSelection(options:)` and `exportScreen(options:)` return copied plain,
terminal, or HTML data. `ExportOptions.terminalState` can additionally emit
the terminal/screen state needed by VT session capture.

Use `hyperlink(at:)` to inspect an OSC 8 link at a visible cell. Terminal
query answers are host policy: configure `setQueryPolicy(_:)`, send focus
transitions only when `isFocusReportingEnabled()` is true, and forward every
resulting `writeToPty` event to the process.

For search, marks, accessibility, and restored positions, use `GridPoint`,
`makeGridAnchor(at:)`, and `cell(at:)`. Anchors track cells through scrolling
and reflow; all points and cell values returned to Swift are copied. These are
inspection APIs, not a replacement for the render transaction in a render loop.

### Engine Controls

`Terminal.libraryInfo()` reports the linked libghostty-vt capabilities and
version. The facade also exposes ANSI/DEC mode reads and writes, cursor reset
defaults, manual title/PWD overrides, Glyph Protocol enablement, and APC input
limits. Set `APCBufferLimits` before accepting untrusted output to bound APC
and Kitty graphics buffering.

### Kitty Graphics

`GhosttyVtGraphics` is an optional product that keeps Kitty image inspection
out of the core terminal surface:

```swift
import GhosttyVt
import GhosttyVtGraphics

let isAvailable = try terminal.configureKittyGraphics(.init())
let snapshot = try terminal.kittyGraphicsSnapshot()
```

It returns copied image metadata/pixels and placement render geometry. Cache
textures using image generations; placement geometry can still change when the
viewport scrolls. Graphics storage is bounded, and file, temporary-file, and
shared-memory media all default to disabled. To accept PNG payloads, install a
process-wide `KittyGraphics.PNGDecoder` before feeding graphics data. The host
chooses decoding and owns all textures and rendering. Each placement also has a
copied screen-coordinate `gridBounds` when it is not virtual.

### Raw API

For an API not yet covered by the Swift facade, import the separate raw
overlay:

```swift
import GhosttyVtRaw
```

`GhosttyVtRaw` re-exports Ghostty's C API from `include/ghostty/vt.h`.

### Platforms

Minimal supported: macOS 14, iOS 17, and macCatalyst 17.

### Acknowledgements

- [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) for `libghostty-vt`
- [Lakr233/libghostty-spm](https://github.com/Lakr233/libghostty-spm) for packaging reference

### License

Copyright © 2026 Yu

Open sourced under the [MIT](/LICENSE) license
