import Foundation
import GhosttyVtRaw

extension Terminal {
    public enum Event: Sendable, Equatable {
        /// Bytes libghostty-vt needs written back to the pty.
        case writeToPty(Data)
        case bell
        case titleChanged(String)
        /// `nil` indicates that the shell cleared its reported working directory.
        case workingDirectoryChanged(String?)
    }

    /// Returns and clears effects produced while processing terminal output.
    public func drainEvents() -> [Event] {
        withTerminalLock {
            let events = pendingEvents
            pendingEvents.removeAll(keepingCapacity: true)
            return events
        }
    }

    func configureEffects() throws {
        let userdata = Unmanaged.passUnretained(self).toOpaque()
        try Self.check(
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_USERDATA, UnsafeRawPointer(userdata))
        )
        try Self.setEffect(
            on: handle,
            option: GHOSTTY_TERMINAL_OPT_WRITE_PTY,
            callback: Self.writePtyCallback
        )
        try Self.setEffect(
            on: handle,
            option: GHOSTTY_TERMINAL_OPT_BELL,
            callback: Self.bellCallback
        )
        try Self.setEffect(
            on: handle,
            option: GHOSTTY_TERMINAL_OPT_TITLE_CHANGED,
            callback: Self.titleChangedCallback
        )
        try Self.setEffect(
            on: handle,
            option: GHOSTTY_TERMINAL_OPT_PWD_CHANGED,
            callback: Self.pwdChangedCallback
        )
    }

    private static let writePtyCallback: @convention(c) (
        OpaquePointer?,
        UnsafeMutableRawPointer?,
        UnsafePointer<UInt8>?,
        Int
    ) -> Void = { _, userdata, bytes, count in
        guard let terminal = terminal(from: userdata), count > 0, let bytes else { return }
        terminal.pendingEvents.append(.writeToPty(Data(bytes: bytes, count: count)))
    }

    private static let bellCallback: @convention(c) (
        OpaquePointer?,
        UnsafeMutableRawPointer?
    ) -> Void = { _, userdata in
        terminal(from: userdata)?.pendingEvents.append(.bell)
    }

    private static let titleChangedCallback: @convention(c) (
        OpaquePointer?,
        UnsafeMutableRawPointer?
    ) -> Void = { handle, userdata in
        guard let terminal = terminal(from: userdata) else { return }
        guard let title = terminal.terminalString(from: handle, data: GHOSTTY_TERMINAL_DATA_TITLE) else { return }
        terminal.pendingEvents.append(.titleChanged(title))
    }

    private static let pwdChangedCallback: @convention(c) (
        OpaquePointer?,
        UnsafeMutableRawPointer?
    ) -> Void = { handle, userdata in
        guard let terminal = terminal(from: userdata) else { return }
        let directory = terminal.terminalString(from: handle, data: GHOSTTY_TERMINAL_DATA_PWD)
        terminal.pendingEvents.append(.workingDirectoryChanged(directory?.isEmpty == true ? nil : directory))
    }

    private static func setEffect<Callback>(
        on terminal: OpaquePointer,
        option: GhosttyTerminalOption,
        callback: Callback
    ) throws {
        let pointer = unsafeBitCast(callback, to: UnsafeRawPointer.self)
        try check(ghostty_terminal_set(terminal, option, pointer))
    }

    private static func terminal(from userdata: UnsafeMutableRawPointer?) -> Terminal? {
        userdata.map { Unmanaged<Terminal>.fromOpaque($0).takeUnretainedValue() }
    }

    func terminalString(
        from terminal: OpaquePointer?,
        data: GhosttyTerminalData
    ) -> String? {
        var string = GhosttyString()
        guard ghostty_terminal_get(terminal, data, &string) == GHOSTTY_SUCCESS else {
            return nil
        }
        guard string.len > 0, let pointer = string.ptr else {
            return ""
        }
        return String(decoding: UnsafeBufferPointer(start: pointer, count: string.len), as: UTF8.self)
    }
}
