### Ghostty VT Swift Package

Swift Package wrapper for upstream [`libghostty-vt`](https://github.com/ghostty-org/ghostty).

### Usage

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
