import Foundation
import GhosttyVtRaw

extension Terminal {
    private static let bracketedPasteMode = ghostty_mode_new(2004, false)

    /// Encodes a key event using the terminal's current input modes.
    public func encode(_ event: KeyEvent) throws -> Data {
        try withTerminalLock {
            ghostty_key_encoder_setopt_from_terminal(keyEncoder, handle)
            ghostty_key_event_set_action(keyEvent, Self.keyAction(from: event.action))
            ghostty_key_event_set_key(keyEvent, try Self.key(from: event.key))
            ghostty_key_event_set_mods(keyEvent, event.modifiers.rawValue)
            ghostty_key_event_set_consumed_mods(keyEvent, event.consumedModifiers.rawValue)
            ghostty_key_event_set_composing(keyEvent, event.isComposing)
            ghostty_key_event_set_unshifted_codepoint(keyEvent, event.unshiftedCodepoint ?? 0)

            guard let text = event.text, !text.isEmpty else {
                ghostty_key_event_set_utf8(keyEvent, nil, 0)
                return try encodedInput { buffer, capacity, written in
                    ghostty_key_encoder_encode(keyEncoder, keyEvent, buffer, capacity, written)
                }
            }

            var utf8Text = text
            return try utf8Text.withUTF8 { utf8 in
                let pointer = utf8.baseAddress.map {
                    UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)
                }
                ghostty_key_event_set_utf8(keyEvent, pointer, utf8.count)
                return try encodedInput { buffer, capacity, written in
                    ghostty_key_encoder_encode(keyEncoder, keyEvent, buffer, capacity, written)
                }
            }
        }
    }

    /// Encodes a normalized mouse event using the terminal's active reporting mode.
    public func encode(_ event: MouseEvent, geometry: MouseGeometry) throws -> Data {
        guard geometry.cellWidth > 0, geometry.cellHeight > 0 else {
            throw TerminalError.invalidMouseGeometry
        }

        return try withTerminalLock {
            let buttonMask = try event.button.map(Self.mouseButtonMask(for:)) ?? 0
            if event.action == .press {
                pressedMouseButtons |= buttonMask
            }
            defer {
                if event.action == .release {
                    pressedMouseButtons &= ~buttonMask
                }
            }

            ghostty_mouse_encoder_setopt_from_terminal(mouseEncoder, handle)

            var size = GhosttyMouseEncoderSize()
            size.size = MemoryLayout<GhosttyMouseEncoderSize>.size
            size.screen_width = geometry.screenWidth
            size.screen_height = geometry.screenHeight
            size.cell_width = geometry.cellWidth
            size.cell_height = geometry.cellHeight
            size.padding_top = geometry.paddingTop
            size.padding_bottom = geometry.paddingBottom
            size.padding_right = geometry.paddingRight
            size.padding_left = geometry.paddingLeft
            ghostty_mouse_encoder_setopt(mouseEncoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size)

            var anyButtonPressed = pressedMouseButtons != 0
            ghostty_mouse_encoder_setopt(
                mouseEncoder,
                GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED,
                &anyButtonPressed
            )

            ghostty_mouse_event_set_action(mouseEvent, Self.mouseAction(from: event.action))
            if let button = event.button {
                ghostty_mouse_event_set_button(mouseEvent, try Self.mouseButton(from: button))
            } else {
                ghostty_mouse_event_clear_button(mouseEvent)
            }
            ghostty_mouse_event_set_mods(mouseEvent, event.modifiers.rawValue)
            ghostty_mouse_event_set_position(
                mouseEvent,
                .init(x: event.position.x, y: event.position.y)
            )

            return try encodedInput { buffer, capacity, written in
                ghostty_mouse_encoder_encode(mouseEncoder, mouseEvent, buffer, capacity, written)
            }
        }
    }

    /// Encodes paste data using the terminal's active bracketed-paste mode.
    public func encodePaste(_ data: Data) throws -> Data {
        try withTerminalLock {
            var bracketed = false
            try Self.check(ghostty_terminal_mode_get(handle, Self.bracketedPasteMode, &bracketed))
            return try Self.encodePaste(data, bracketed: bracketed)
        }
    }

    /// Encodes UTF-8 paste text using the terminal's active bracketed-paste mode.
    public func encodePaste(_ text: String) throws -> Data {
        try encodePaste(Data(text.utf8))
    }

    /// Returns whether data is free of the paste sequences Ghostty treats as unsafe.
    public static func isPasteSafe(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }

        return data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return true }
            return ghostty_paste_is_safe(
                baseAddress.assumingMemoryBound(to: CChar.self),
                bytes.count
            )
        }
    }

    /// Returns whether UTF-8 text is free of the paste sequences Ghostty treats as unsafe.
    public static func isPasteSafe(_ text: String) -> Bool {
        isPasteSafe(Data(text.utf8))
    }

    private func encodedInput(
        _ encode: (UnsafeMutablePointer<CChar>?, Int, UnsafeMutablePointer<Int>) -> GhosttyResult
    ) throws -> Data {
        var written = 0
        var result = inputBuffer.withUnsafeMutableBytes { bytes in
            encode(bytes.baseAddress?.assumingMemoryBound(to: CChar.self), bytes.count, &written)
        }

        if result == GHOSTTY_OUT_OF_SPACE {
            guard written > inputBuffer.count else {
                throw TerminalError.unexpectedResult
            }
            inputBuffer = [UInt8](repeating: 0, count: written)
            written = 0
            result = inputBuffer.withUnsafeMutableBytes { bytes in
                encode(bytes.baseAddress?.assumingMemoryBound(to: CChar.self), bytes.count, &written)
            }
        }

        try Self.check(result)
        guard written <= inputBuffer.count else {
            throw TerminalError.unexpectedResult
        }
        return Data(inputBuffer.prefix(written))
    }

    private static func encodePaste(_ data: Data, bracketed: Bool) throws -> Data {
        var input = [UInt8](data)
        var output = Data(repeating: 0, count: input.count + (bracketed ? 12 : 0))
        var written = 0

        let result = input.withUnsafeMutableBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                ghostty_paste_encode(
                    inputBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                    inputBytes.count,
                    bracketed,
                    outputBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                    outputBytes.count,
                    &written
                )
            }
        }
        try Self.check(result)
        guard written <= output.count else {
            throw TerminalError.unexpectedResult
        }
        output.removeSubrange(written ..< output.count)
        return output
    }

    private static func keyAction(from action: KeyEvent.Action) -> GhosttyKeyAction {
        switch action {
        case .press:
            return GHOSTTY_KEY_ACTION_PRESS
        case .release:
            return GHOSTTY_KEY_ACTION_RELEASE
        case .repeatPress:
            return GHOSTTY_KEY_ACTION_REPEAT
        }
    }

    private static func key(from key: KeyEvent.Key) throws -> GhosttyKey {
        switch key {
        case .text:
            return GHOSTTY_KEY_UNIDENTIFIED
        case .backspace:
            return GHOSTTY_KEY_BACKSPACE
        case .tab:
            return GHOSTTY_KEY_TAB
        case .enter:
            return GHOSTTY_KEY_ENTER
        case .escape:
            return GHOSTTY_KEY_ESCAPE
        case .space:
            return GHOSTTY_KEY_SPACE
        case .arrowUp:
            return GHOSTTY_KEY_ARROW_UP
        case .arrowDown:
            return GHOSTTY_KEY_ARROW_DOWN
        case .arrowLeft:
            return GHOSTTY_KEY_ARROW_LEFT
        case .arrowRight:
            return GHOSTTY_KEY_ARROW_RIGHT
        case .home:
            return GHOSTTY_KEY_HOME
        case .end:
            return GHOSTTY_KEY_END
        case .pageUp:
            return GHOSTTY_KEY_PAGE_UP
        case .pageDown:
            return GHOSTTY_KEY_PAGE_DOWN
        case .insert:
            return GHOSTTY_KEY_INSERT
        case .delete:
            return GHOSTTY_KEY_DELETE
        case .function(let number):
            switch number {
            case 1: return GHOSTTY_KEY_F1
            case 2: return GHOSTTY_KEY_F2
            case 3: return GHOSTTY_KEY_F3
            case 4: return GHOSTTY_KEY_F4
            case 5: return GHOSTTY_KEY_F5
            case 6: return GHOSTTY_KEY_F6
            case 7: return GHOSTTY_KEY_F7
            case 8: return GHOSTTY_KEY_F8
            case 9: return GHOSTTY_KEY_F9
            case 10: return GHOSTTY_KEY_F10
            case 11: return GHOSTTY_KEY_F11
            case 12: return GHOSTTY_KEY_F12
            case 13: return GHOSTTY_KEY_F13
            case 14: return GHOSTTY_KEY_F14
            case 15: return GHOSTTY_KEY_F15
            case 16: return GHOSTTY_KEY_F16
            case 17: return GHOSTTY_KEY_F17
            case 18: return GHOSTTY_KEY_F18
            case 19: return GHOSTTY_KEY_F19
            case 20: return GHOSTTY_KEY_F20
            case 21: return GHOSTTY_KEY_F21
            case 22: return GHOSTTY_KEY_F22
            case 23: return GHOSTTY_KEY_F23
            case 24: return GHOSTTY_KEY_F24
            case 25: return GHOSTTY_KEY_F25
            default: throw TerminalError.invalidKey
            }
        }
    }

    private static func mouseAction(from action: MouseEvent.Action) -> GhosttyMouseAction {
        switch action {
        case .press:
            return GHOSTTY_MOUSE_ACTION_PRESS
        case .release:
            return GHOSTTY_MOUSE_ACTION_RELEASE
        case .motion:
            return GHOSTTY_MOUSE_ACTION_MOTION
        }
    }

    private static func mouseButton(from button: MouseEvent.Button) throws -> GhosttyMouseButton {
        switch button {
        case .left:
            return GHOSTTY_MOUSE_BUTTON_LEFT
        case .right:
            return GHOSTTY_MOUSE_BUTTON_RIGHT
        case .middle:
            return GHOSTTY_MOUSE_BUTTON_MIDDLE
        case .other(let number):
            switch number {
            case 4: return GHOSTTY_MOUSE_BUTTON_FOUR
            case 5: return GHOSTTY_MOUSE_BUTTON_FIVE
            case 6: return GHOSTTY_MOUSE_BUTTON_SIX
            case 7: return GHOSTTY_MOUSE_BUTTON_SEVEN
            case 8: return GHOSTTY_MOUSE_BUTTON_EIGHT
            case 9: return GHOSTTY_MOUSE_BUTTON_NINE
            case 10: return GHOSTTY_MOUSE_BUTTON_TEN
            case 11: return GHOSTTY_MOUSE_BUTTON_ELEVEN
            default: throw TerminalError.invalidMouseButton
            }
        }
    }

    private static func mouseButtonMask(for button: MouseEvent.Button) throws -> UInt16 {
        let index: UInt8
        switch button {
        case .left:
            index = 1
        case .right:
            index = 2
        case .middle:
            index = 3
        case .other(let number):
            guard (4 ... 11).contains(number) else {
                throw TerminalError.invalidMouseButton
            }
            index = number
        }
        return UInt16(1) << (index - 1)
    }
}
