import Foundation

// MARK: - The 5 Programmable Dial Inputs

public enum DialSlot: Int, CaseIterable, Identifiable, Codable, Sendable {
    case turnLeft = 1          // 左上: Turn Left (CCW)
    case turnRight = 2         // 右上: Turn Right (CW)
    case clickAndTurnLeft = 3  // 左下: Click & Turn Left (Press + CCW)
    case clickAndTurnRight = 4 // 右下: Click & Turn Right (Press + CW)
    case click = 5             // 中间: Click (Center Press)

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .turnLeft: return "Turn Left"
        case .turnRight: return "Turn Right"
        case .click: return "Click"
        case .clickAndTurnLeft: return "Click + Turn Left"
        case .clickAndTurnRight: return "Click + Turn Right"
        }
    }

    public var subtitle: String {
        switch self {
        case .turnLeft: return "Rotate Counter-Clockwise (CCW)"
        case .turnRight: return "Rotate Clockwise (CW)"
        case .click: return "Press Dial Down"
        case .clickAndTurnLeft: return "Hold Down & Rotate CCW"
        case .clickAndTurnRight: return "Hold Down & Rotate CW"
        }
    }

    public var cliName: String {
        switch self {
        case .turnLeft: return "turn-left"
        case .turnRight: return "turn-right"
        case .click: return "click"
        case .clickAndTurnLeft: return "click-left"
        case .clickAndTurnRight: return "click-right"
        }
    }

    public var systemSymbolName: String {
        switch self {
        case .turnLeft: return "arrow.counterclockwise"
        case .turnRight: return "arrow.clockwise"
        case .click: return "circle.inset.filled"
        case .clickAndTurnLeft: return "arrow.uturn.backward.circle.fill"
        case .clickAndTurnRight: return "arrow.uturn.forward.circle.fill"
        }
    }

    /// Primary command byte at offset 2 (`03 FD <cmd> ...`)
    public var primaryCommandCode: UInt8 {
        switch self {
        case .turnLeft: return 0x02
        case .click: return 0x03
        case .turnRight: return 0x04
        case .clickAndTurnLeft: return 0x05
        case .clickAndTurnRight: return 0x06
        }
    }

    /// Legacy/companion command byte cloned by `sendPacketWithResult`
    public var legacyCommandCode: UInt8 {
        switch self {
        case .turnLeft: return 0x10
        case .click: return 0x11
        case .turnRight: return 0x12
        case .clickAndTurnLeft: return 0x13
        case .clickAndTurnRight: return 0x15
        }
    }

    /// Factory default action for each slot (`clearSelectedKeys` at `0x10004b562`)
    public var factoryDefaultAction: DialAction {
        switch self {
        case .turnLeft: return .multimedia(.volumeDown)
        case .turnRight: return .multimedia(.volumeUp)
        case .click: return .multimedia(.mute)
        case .clickAndTurnLeft: return .multimedia(.brightnessDown)
        case .clickAndTurnRight: return .multimedia(.brightnessUp)
        }
    }

    public static func from(commandCode: UInt8) -> DialSlot? {
        switch commandCode {
        case 0x02, 0x10: return .turnLeft
        case 0x03, 0x11: return .click
        case 0x04, 0x12: return .turnRight
        case 0x05, 0x13: return .clickAndTurnLeft
        case 0x06, 0x15: return .clickAndTurnRight
        default: return nil
        }
    }

    public static func from(cliName: String) -> DialSlot? {
        let normalized = cliName.lowercased().replacingOccurrences(of: "_", with: "-")
        switch normalized {
        case "turn-left", "left", "ccw", "1": return .turnLeft
        case "turn-right", "right", "cw", "2": return .turnRight
        case "click", "press", "center", "5": return .click
        case "click-left", "click-turn-left", "press-left", "3": return .clickAndTurnLeft
        case "click-right", "click-turn-right", "press-right", "4": return .clickAndTurnRight
        default: return nil
        }
    }
}

// MARK: - Modifier Prefix Keys (0xF1..0xF9)

public struct VK01Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let leftControl  = VK01Modifiers(rawValue: 1 << 0) // 0xF1
    public static let leftShift    = VK01Modifiers(rawValue: 1 << 1) // 0xF2
    public static let leftOption   = VK01Modifiers(rawValue: 1 << 2) // 0xF3
    public static let leftCommand  = VK01Modifiers(rawValue: 1 << 3) // 0xF4
    public static let rightControl = VK01Modifiers(rawValue: 1 << 4) // 0xF5
    public static let rightShift   = VK01Modifiers(rawValue: 1 << 5) // 0xF6
    public static let rightOption  = VK01Modifiers(rawValue: 1 << 6) // 0xF7
    public static let rightCommand = VK01Modifiers(rawValue: 1 << 7) // 0xF8
    public static let fn           = VK01Modifiers(rawValue: 1 << 8) // 0xF9

    /// Ordered modifier prefix keycodes matching `modifierPrefixKeys` (`0x100058ed0`)
    public var prefixKeyCodes: [UInt8] {
        var codes: [UInt8] = []
        if contains(.leftControl)  { codes.append(0xF1) }
        if contains(.rightControl) { codes.append(0xF5) }
        if contains(.leftShift)    { codes.append(0xF2) }
        if contains(.rightShift)   { codes.append(0xF6) }
        if contains(.leftOption)   { codes.append(0xF3) }
        if contains(.rightOption)  { codes.append(0xF7) }
        if contains(.leftCommand)  { codes.append(0xF4) }
        if contains(.rightCommand) { codes.append(0xF8) }
        if contains(.fn)           { codes.append(0xF9) }
        return codes
    }

    public static func from(prefixKeyCode: UInt8) -> VK01Modifiers? {
        switch prefixKeyCode {
        case 0xF1: return .leftControl
        case 0xF2: return .leftShift
        case 0xF3: return .leftOption
        case 0xF4: return .leftCommand
        case 0xF5: return .rightControl
        case 0xF6: return .rightShift
        case 0xF7: return .rightOption
        case 0xF8: return .rightCommand
        case 0xF9: return .fn
        default: return nil
        }
    }

    public var displaySymbols: String {
        var parts: [String] = []
        if contains(.leftControl) || contains(.rightControl) { parts.append("⌃") }
        if contains(.leftOption)  || contains(.rightOption)  { parts.append("⌥") }
        if contains(.leftShift)   || contains(.rightShift)   { parts.append("⇧") }
        if contains(.leftCommand) || contains(.rightCommand) { parts.append("⌘") }
        if contains(.fn) { parts.append("fn ") }
        return parts.joined()
    }

    public var readableNames: [String] {
        var names: [String] = []
        if contains(.leftControl)  { names.append("Ctrl") }
        if contains(.rightControl) { names.append("RightCtrl") }
        if contains(.leftOption)   { names.append("Option") }
        if contains(.rightOption)  { names.append("RightOption") }
        if contains(.leftShift)    { names.append("Shift") }
        if contains(.rightShift)   { names.append("RightShift") }
        if contains(.leftCommand)  { names.append("Command") }
        if contains(.rightCommand) { names.append("RightCommand") }
        if contains(.fn)           { names.append("fn") }
        return names
    }
}

// MARK: - Standard HID Keycodes (Type 0x01)

public struct VK01Key: Identifiable, Hashable, Codable, Sendable {
    public let code: UInt8
    public let label: String
    public let category: String

    public var id: UInt8 { code }

    public init(code: UInt8, label: String, category: String = "General") {
        self.code = code
        self.label = label
        self.category = category
    }

    public static let allKeys: [VK01Key] = [
        // Letters
        VK01Key(code: 0x04, label: "A", category: "Letters"),
        VK01Key(code: 0x05, label: "B", category: "Letters"),
        VK01Key(code: 0x06, label: "C", category: "Letters"),
        VK01Key(code: 0x07, label: "D", category: "Letters"),
        VK01Key(code: 0x08, label: "E", category: "Letters"),
        VK01Key(code: 0x09, label: "F", category: "Letters"),
        VK01Key(code: 0x0A, label: "G", category: "Letters"),
        VK01Key(code: 0x0B, label: "H", category: "Letters"),
        VK01Key(code: 0x0C, label: "I", category: "Letters"),
        VK01Key(code: 0x0D, label: "J", category: "Letters"),
        VK01Key(code: 0x0E, label: "K", category: "Letters"),
        VK01Key(code: 0x0F, label: "L", category: "Letters"),
        VK01Key(code: 0x10, label: "M", category: "Letters"),
        VK01Key(code: 0x11, label: "N", category: "Letters"),
        VK01Key(code: 0x12, label: "O", category: "Letters"),
        VK01Key(code: 0x13, label: "P", category: "Letters"),
        VK01Key(code: 0x14, label: "Q", category: "Letters"),
        VK01Key(code: 0x15, label: "R", category: "Letters"),
        VK01Key(code: 0x16, label: "S", category: "Letters"),
        VK01Key(code: 0x17, label: "T", category: "Letters"),
        VK01Key(code: 0x18, label: "U", category: "Letters"),
        VK01Key(code: 0x19, label: "V", category: "Letters"),
        VK01Key(code: 0x1A, label: "W", category: "Letters"),
        VK01Key(code: 0x1B, label: "X", category: "Letters"),
        VK01Key(code: 0x1C, label: "Y", category: "Letters"),
        VK01Key(code: 0x1D, label: "Z", category: "Letters"),

        // Numbers
        VK01Key(code: 0x1E, label: "1", category: "Numbers"),
        VK01Key(code: 0x1F, label: "2", category: "Numbers"),
        VK01Key(code: 0x20, label: "3", category: "Numbers"),
        VK01Key(code: 0x21, label: "4", category: "Numbers"),
        VK01Key(code: 0x22, label: "5", category: "Numbers"),
        VK01Key(code: 0x23, label: "6", category: "Numbers"),
        VK01Key(code: 0x24, label: "7", category: "Numbers"),
        VK01Key(code: 0x25, label: "8", category: "Numbers"),
        VK01Key(code: 0x26, label: "9", category: "Numbers"),
        VK01Key(code: 0x27, label: "0", category: "Numbers"),

        // Navigation & Editing
        VK01Key(code: 0x28, label: "Return", category: "Navigation & Editing"),
        VK01Key(code: 0x29, label: "Esc", category: "Navigation & Editing"),
        VK01Key(code: 0x2A, label: "Backspace", category: "Navigation & Editing"),
        VK01Key(code: 0x2B, label: "Tab", category: "Navigation & Editing"),
        VK01Key(code: 0x2C, label: "Space", category: "Navigation & Editing"),
        VK01Key(code: 0x39, label: "CapsLock", category: "Navigation & Editing"),
        VK01Key(code: 0x49, label: "Insert", category: "Navigation & Editing"),
        VK01Key(code: 0x4A, label: "Home", category: "Navigation & Editing"),
        VK01Key(code: 0x4B, label: "PageUp", category: "Navigation & Editing"),
        VK01Key(code: 0x4C, label: "Delete", category: "Navigation & Editing"),
        VK01Key(code: 0x4D, label: "End", category: "Navigation & Editing"),
        VK01Key(code: 0x4E, label: "PageDown", category: "Navigation & Editing"),
        VK01Key(code: 0x4F, label: "Right", category: "Navigation & Editing"),
        VK01Key(code: 0x50, label: "Left", category: "Navigation & Editing"),
        VK01Key(code: 0x51, label: "Down", category: "Navigation & Editing"),
        VK01Key(code: 0x52, label: "Up", category: "Navigation & Editing"),

        // Punctuation & Symbols
        VK01Key(code: 0x2D, label: "-", category: "Symbols"),
        VK01Key(code: 0x2E, label: "=", category: "Symbols"),
        VK01Key(code: 0x2F, label: "[", category: "Symbols"),
        VK01Key(code: 0x30, label: "]", category: "Symbols"),
        VK01Key(code: 0x31, label: "\\", category: "Symbols"),
        VK01Key(code: 0x33, label: ";", category: "Symbols"),
        VK01Key(code: 0x34, label: "'", category: "Symbols"),
        VK01Key(code: 0x35, label: "`", category: "Symbols"),
        VK01Key(code: 0x36, label: ",", category: "Symbols"),
        VK01Key(code: 0x37, label: ".", category: "Symbols"),
        VK01Key(code: 0x38, label: "/", category: "Symbols"),

        // Function Keys F1..F24
        VK01Key(code: 0x3A, label: "F1", category: "Function Keys"),
        VK01Key(code: 0x3B, label: "F2", category: "Function Keys"),
        VK01Key(code: 0x3C, label: "F3", category: "Function Keys"),
        VK01Key(code: 0x3D, label: "F4", category: "Function Keys"),
        VK01Key(code: 0x3E, label: "F5", category: "Function Keys"),
        VK01Key(code: 0x3F, label: "F6", category: "Function Keys"),
        VK01Key(code: 0x40, label: "F7", category: "Function Keys"),
        VK01Key(code: 0x41, label: "F8", category: "Function Keys"),
        VK01Key(code: 0x42, label: "F9", category: "Function Keys"),
        VK01Key(code: 0x43, label: "F10", category: "Function Keys"),
        VK01Key(code: 0x44, label: "F11", category: "Function Keys"),
        VK01Key(code: 0x45, label: "F12", category: "Function Keys"),
        VK01Key(code: 0x68, label: "F13", category: "Function Keys"),
        VK01Key(code: 0x69, label: "F14", category: "Function Keys"),
        VK01Key(code: 0x6A, label: "F15", category: "Function Keys"),
        VK01Key(code: 0x6B, label: "F16", category: "Function Keys"),
        VK01Key(code: 0x6C, label: "F17", category: "Function Keys"),
        VK01Key(code: 0x6D, label: "F18", category: "Function Keys"),
        VK01Key(code: 0x6E, label: "F19", category: "Function Keys"),
        VK01Key(code: 0x6F, label: "F20", category: "Function Keys"),
        VK01Key(code: 0x70, label: "F21", category: "Function Keys"),
        VK01Key(code: 0x71, label: "F22", category: "Function Keys"),
        VK01Key(code: 0x72, label: "F23", category: "Function Keys"),
        VK01Key(code: 0x73, label: "F24", category: "Function Keys"),

        // Keypad
        VK01Key(code: 0x53, label: "NumLock", category: "Keypad"),
        VK01Key(code: 0x54, label: "Num/", category: "Keypad"),
        VK01Key(code: 0x55, label: "Num*", category: "Keypad"),
        VK01Key(code: 0x56, label: "Num-", category: "Keypad"),
        VK01Key(code: 0x57, label: "Num+", category: "Keypad"),
        VK01Key(code: 0x58, label: "NumEnter", category: "Keypad"),
        VK01Key(code: 0x59, label: "Num1", category: "Keypad"),
        VK01Key(code: 0x5A, label: "Num2", category: "Keypad"),
        VK01Key(code: 0x5B, label: "Num3", category: "Keypad"),
        VK01Key(code: 0x5C, label: "Num4", category: "Keypad"),
        VK01Key(code: 0x5D, label: "Num5", category: "Keypad"),
        VK01Key(code: 0x5E, label: "Num6", category: "Keypad"),
        VK01Key(code: 0x5F, label: "Num7", category: "Keypad"),
        VK01Key(code: 0x60, label: "Num8", category: "Keypad"),
        VK01Key(code: 0x61, label: "Num9", category: "Keypad"),
        VK01Key(code: 0x62, label: "Num0", category: "Keypad"),
        VK01Key(code: 0x63, label: "Num.", category: "Keypad"),

        // Standalone Modifiers
        VK01Key(code: 0xF1, label: "Left Control", category: "Modifiers"),
        VK01Key(code: 0xF2, label: "Left Shift", category: "Modifiers"),
        VK01Key(code: 0xF3, label: "Left Option", category: "Modifiers"),
        VK01Key(code: 0xF4, label: "Left Command", category: "Modifiers"),
        VK01Key(code: 0xF5, label: "Right Control", category: "Modifiers"),
        VK01Key(code: 0xF6, label: "Right Shift", category: "Modifiers"),
        VK01Key(code: 0xF7, label: "Right Option", category: "Modifiers"),
        VK01Key(code: 0xF8, label: "Right Command", category: "Modifiers"),
        VK01Key(code: 0xF9, label: "fn", category: "Modifiers")
    ]

    public static let byCode: [UInt8: VK01Key] = {
        Dictionary(uniqueKeysWithValues: allKeys.map { ($0.code, $0) })
    }()

    public static func from(label: String) -> VK01Key? {
        let lower = label.lowercased()
        if let match = allKeys.first(where: { $0.label.lowercased() == lower }) {
            return match
        }
        switch lower {
        case "enter", "return": return byCode[0x28]
        case "escape", "esc": return byCode[0x29]
        case "bksp", "backspace": return byCode[0x2A]
        case "del", "delete": return byCode[0x4C]
        case "pgup", "pageup": return byCode[0x4B]
        case "pgdn", "pagedown": return byCode[0x4E]
        case "plus", "=": return byCode[0x2E]
        case "minus", "-": return byCode[0x2D]
        case "comma", ",": return byCode[0x36]
        case "period", "dot", ".": return byCode[0x37]
        case "slash", "/": return byCode[0x38]
        case "lbracket", "[": return byCode[0x2F]
        case "rbracket", "]": return byCode[0x30]
        case "backslash", "\\": return byCode[0x31]
        case "semicolon", ";": return byCode[0x33]
        case "quote", "'": return byCode[0x34]
        case "grave", "tilde", "`": return byCode[0x35]
        default: return nil
        }
    }

    /// Maps macOS `NSEvent.keyCode` (Carbon virtual keycode) to USB HID usage ID
    public static func from(macOSVirtualKeyCode: UInt16) -> UInt8? {
        switch macOSVirtualKeyCode {
        case 0x00: return 0x04 // A
        case 0x0B: return 0x05 // B
        case 0x08: return 0x06 // C
        case 0x02: return 0x07 // D
        case 0x0E: return 0x08 // E
        case 0x03: return 0x09 // F
        case 0x05: return 0x0A // G
        case 0x04: return 0x0B // H
        case 0x22: return 0x0C // I
        case 0x26: return 0x0D // J
        case 0x28: return 0x0E // K
        case 0x25: return 0x0F // L
        case 0x2E: return 0x10 // M
        case 0x2D: return 0x11 // N
        case 0x1F: return 0x12 // O
        case 0x23: return 0x13 // P
        case 0x0C: return 0x14 // Q
        case 0x0F: return 0x15 // R
        case 0x01: return 0x16 // S
        case 0x11: return 0x17 // T
        case 0x20: return 0x18 // U
        case 0x09: return 0x19 // V
        case 0x0D: return 0x1A // W
        case 0x07: return 0x1B // X
        case 0x10: return 0x1C // Y
        case 0x06: return 0x1D // Z
        case 0x12: return 0x1E // 1
        case 0x13: return 0x1F // 2
        case 0x14: return 0x20 // 3
        case 0x15: return 0x21 // 4
        case 0x17: return 0x22 // 5
        case 0x16: return 0x23 // 6
        case 0x1A: return 0x24 // 7
        case 0x1C: return 0x25 // 8
        case 0x19: return 0x26 // 9
        case 0x1D: return 0x27 // 0
        case 0x24: return 0x28 // Return
        case 0x35: return 0x29 // Esc
        case 0x33: return 0x2A // Backspace
        case 0x30: return 0x2B // Tab
        case 0x31: return 0x2C // Space
        case 0x1B: return 0x2D // -
        case 0x18: return 0x2E // =
        case 0x21: return 0x2F // [
        case 0x1E: return 0x30 // ]
        case 0x2A: return 0x31 // \
        case 0x29: return 0x33 // ;
        case 0x27: return 0x34 // '
        case 0x32: return 0x35 // `
        case 0x2B: return 0x36 // ,
        case 0x2F: return 0x37 // .
        case 0x2C: return 0x38 // /
        case 0x39: return 0x39 // CapsLock
        case 0x7A: return 0x3A // F1
        case 0x78: return 0x3B // F2
        case 0x63: return 0x3C // F3
        case 0x76: return 0x3D // F4
        case 0x60: return 0x3E // F5
        case 0x61: return 0x3F // F6
        case 0x62: return 0x40 // F7
        case 0x64: return 0x41 // F8
        case 0x65: return 0x42 // F9
        case 0x6D: return 0x43 // F10
        case 0x67: return 0x44 // F11
        case 0x6F: return 0x45 // F12
        case 0x69: return 0x68 // F13
        case 0x6B: return 0x69 // F14
        case 0x71: return 0x6A // F15
        case 0x6A: return 0x6B // F16
        case 0x40: return 0x6C // F17
        case 0x4F: return 0x6D // F18
        case 0x50: return 0x6E // F19
        case 0x5A: return 0x6F // F20
        case 0x73: return 0x4A // Home
        case 0x74: return 0x4B // PageUp
        case 0x75: return 0x4C // Forward Delete
        case 0x77: return 0x4D // End
        case 0x79: return 0x4E // PageDown
        case 0x7C: return 0x4F // Right
        case 0x7B: return 0x50 // Left
        case 0x7D: return 0x51 // Down
        case 0x7E: return 0x52 // Up
        default: return nil
        }
    }
}

// MARK: - Key Macro Step

public struct VK01MacroStep: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var modifiers: VK01Modifiers
    public var keyCode: UInt8
    public var delayMs: UInt16 // 0..60000 ms

    public init(id: UUID = UUID(), modifiers: VK01Modifiers = [], keyCode: UInt8, delayMs: UInt16 = 0) {
        self.id = id
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.delayMs = min(delayMs, 60000)
    }

    public static func == (lhs: VK01MacroStep, rhs: VK01MacroStep) -> Bool {
        lhs.modifiers == rhs.modifiers && lhs.keyCode == rhs.keyCode && lhs.delayMs == rhs.delayMs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(modifiers)
        hasher.combine(keyCode)
        hasher.combine(delayMs)
    }

    public var displayString: String {
        let keyLabel = VK01Key.byCode[keyCode]?.label ?? String(format: "0x%02X", keyCode)
        let prefix = modifiers.displaySymbols
        if delayMs > 0 {
            return "\(prefix)\(keyLabel) (\(delayMs)ms)"
        }
        return "\(prefix)\(keyLabel)"
    }
}

// MARK: - Multimedia / Consumer Keys (Type 0x02)

public enum VK01MediaKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case volumeUp       = "volume-up"
    case volumeDown     = "volume-down"
    case mute           = "mute"
    case playPause      = "play-pause"
    case nextTrack      = "next-track"
    case prevTrack      = "prev-track"
    case stop           = "stop"
    case brightnessUp   = "brightness-up"
    case brightnessDown = "brightness-down"
    case trebleUp       = "treble-up"
    case trebleDown     = "treble-down"
    case bassUp         = "bass-up"
    case bassDown       = "bass-down"
    case mediaPlayer    = "media-player"
    case email          = "email"
    case calculator     = "calculator"
    case myComputer     = "my-computer"
    case browserHome    = "browser-home"
    case browserBack    = "browser-back"
    case browserForward = "browser-forward"
    case browserRefresh = "browser-refresh"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .volumeUp: return "Volume Up (+)"
        case .volumeDown: return "Volume Down (-)"
        case .mute: return "Mute Audio"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .prevTrack: return "Previous Track"
        case .stop: return "Stop Playback"
        case .brightnessUp: return "Screen Brightness Up (+)"
        case .brightnessDown: return "Screen Brightness Down (-)"
        case .trebleUp: return "Treble +"
        case .trebleDown: return "Treble -"
        case .bassUp: return "Bass +"
        case .bassDown: return "Bass -"
        case .mediaPlayer: return "Launch Media Player"
        case .email: return "Launch Email"
        case .calculator: return "Launch Calculator"
        case .myComputer: return "Open Finder / My Computer"
        case .browserHome: return "Browser Home"
        case .browserBack: return "Browser Back"
        case .browserForward: return "Browser Forward"
        case .browserRefresh: return "Browser Refresh"
        }
    }

    public var systemSymbolName: String {
        switch self {
        case .volumeUp: return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .mute: return "speaker.slash.fill"
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.end.fill"
        case .prevTrack: return "backward.end.fill"
        case .stop: return "stop.fill"
        case .brightnessUp: return "sun.max.fill"
        case .brightnessDown: return "sun.min.fill"
        case .trebleUp, .trebleDown, .bassUp, .bassDown: return "slider.vertical.3"
        case .mediaPlayer: return "music.note.tv"
        case .email: return "envelope.fill"
        case .calculator: return "plus.forwardslash.minus"
        case .myComputer: return "folder.fill"
        case .browserHome: return "house.fill"
        case .browserBack: return "chevron.backward"
        case .browserForward: return "chevron.forward"
        case .browserRefresh: return "arrow.clockwise"
        }
    }

    /// 16-bit Consumer Usage ID (`usage_lo` at byte 9, `usage_hi` at byte 10)
    public var consumerUsage: UInt16 {
        switch self {
        case .volumeUp:       return 0x00E9
        case .volumeDown:     return 0x00EA
        case .mute:           return 0x00E2
        case .playPause:      return 0x00CD
        case .nextTrack:      return 0x00B5
        case .prevTrack:      return 0x00B6
        case .stop:           return 0x00B7
        case .brightnessUp:   return 0x006F
        case .brightnessDown: return 0x0070
        case .trebleDown:     return 0x0152
        case .trebleUp:       return 0x0153
        case .bassDown:       return 0x0154
        case .bassUp:         return 0x0155
        case .mediaPlayer:    return 0x0183
        case .email:          return 0x018A
        case .calculator:     return 0x0192
        case .myComputer:     return 0x0194
        case .browserHome:    return 0x0223
        case .browserBack:    return 0x0224
        case .browserForward: return 0x0225
        case .browserRefresh: return 0x0027
        }
    }

    /// Byte 6 (`subcount`) and Byte 12 (`extFlag`) from `sendMultimediaKey` (`0x100053560`)
    public var packetFlags: (subcount: UInt8, extFlag: UInt8) {
        switch self {
        case .mediaPlayer, .email, .calculator, .myComputer:
            return (0x02, 0x01)
        case .browserHome, .browserBack, .browserForward, .browserRefresh:
            return (0x02, 0x02)
        default:
            return (0x01, 0x00)
        }
    }

    public static func from(consumerUsage: UInt16) -> VK01MediaKey? {
        allCases.first { $0.consumerUsage == consumerUsage }
    }
}

// MARK: - Mouse / Scroll / Swipe / Like Actions (Type 0x03)

public enum VK01MouseAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case leftClick       = "mouse-left"
    case rightClick      = "mouse-right"
    case middleClick     = "mouse-middle"
    case scrollUp        = "scroll-up"
    case scrollDown      = "scroll-down"
    case ctrlScrollUp    = "ctrl-scroll-up"
    case ctrlScrollDown  = "ctrl-scroll-down"
    case shiftScrollUp   = "shift-scroll-up"
    case shiftScrollDown = "shift-scroll-down"
    case optScrollUp     = "opt-scroll-up"
    case optScrollDown   = "opt-scroll-down"
    case swipeLeft       = "swipe-left"
    case swipeRight      = "swipe-right"
    case swipeUp         = "swipe-up"
    case swipeDown       = "swipe-down"
    case likeDoubleTap   = "like"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftClick:       return "Mouse Left Click"
        case .rightClick:      return "Mouse Right Click"
        case .middleClick:     return "Mouse Middle Click"
        case .scrollUp:        return "Scroll Wheel Up (+)"
        case .scrollDown:      return "Scroll Wheel Down (-)"
        case .ctrlScrollUp:    return "⌃ Ctrl + Scroll Up (Zoom In)"
        case .ctrlScrollDown:  return "⌃ Ctrl + Scroll Down (Zoom Out)"
        case .shiftScrollUp:   return "⇧ Shift + Scroll Up (Horizontal)"
        case .shiftScrollDown: return "⇧ Shift + Scroll Down (Horizontal)"
        case .optScrollUp:     return "⌥ Option + Scroll Up"
        case .optScrollDown:   return "⌥ Option + Scroll Down"
        case .swipeLeft:       return "Gesture: Swipe Left"
        case .swipeRight:      return "Gesture: Swipe Right"
        case .swipeUp:         return "Gesture: Swipe Up"
        case .swipeDown:       return "Gesture: Swipe Down"
        case .likeDoubleTap:   return "Gesture: Like / Double-Tap"
        }
    }
}

// MARK: - Procreate Shortcuts (Type 0x04)

public enum VK01ProcreateAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case brushSizeIncrease = "procreate-brush-up"     // ] (0x30)
    case brushSizeDecrease = "procreate-brush-down"   // [ (0x2F)
    case brushSizeFineUp   = "procreate-fine-up"      // Cmd + ] (0xF4, 0x30)
    case brushSizeFineDown = "procreate-fine-down"    // Cmd + [ (0xF4, 0x2F)
    case undo              = "procreate-undo"         // Cmd + Z (0xF4, 0x1D)
    case redo              = "procreate-redo"         // Cmd + Shift + Z (0xF4, 0xF2, 0x1D)
    case quickMenu         = "procreate-quickmenu"    // Space (0x2C)
    case fullScreen        = "procreate-fullscreen"   // Cmd + 0 (0xF4, 0x27)
    case clearLayer        = "procreate-clear-layer"  // Cmd + Backspace (0xF4, 0x2A)
    case cut               = "procreate-cut"          // Cmd + X (0xF4, 0x1B)
    case copy              = "procreate-copy"         // Cmd + C (0xF4, 0x06)
    case paste             = "procreate-paste"        // Cmd + V (0xF4, 0x19)
    case colorBalance      = "procreate-color-balance"// Cmd + B (0xF4, 0x05)
    case hueSaturation     = "procreate-hsb"          // Cmd + U (0xF4, 0x18)

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brushSizeIncrease: return "Procreate: Brush Size + (])"
        case .brushSizeDecrease: return "Procreate: Brush Size - ([)"
        case .brushSizeFineUp:   return "Procreate: Fine Brush + (⌘])"
        case .brushSizeFineDown: return "Procreate: Fine Brush - (⌘[)"
        case .undo:              return "Procreate: Undo (⌘Z)"
        case .redo:              return "Procreate: Redo (⇧⌘Z)"
        case .quickMenu:         return "Procreate: QuickMenu (Space)"
        case .fullScreen:        return "Procreate: Full Screen (⌘0)"
        case .clearLayer:        return "Procreate: Clear Layer (⌘⌫)"
        case .cut:               return "Procreate: Cut (⌘X)"
        case .copy:              return "Procreate: Copy (⌘C)"
        case .paste:             return "Procreate: Paste (⌘V)"
        case .colorBalance:      return "Procreate: Color Balance (⌘B)"
        case .hueSaturation:     return "Procreate: Hue/Saturation (⌘U)"
        }
    }

    public var keyCodes: [UInt8] {
        switch self {
        case .brushSizeIncrease: return [0x30]
        case .brushSizeDecrease: return [0x2F]
        case .brushSizeFineUp:   return [0xF4, 0x30]
        case .brushSizeFineDown: return [0xF4, 0x2F]
        case .undo:              return [0xF4, 0x1D]
        case .redo:              return [0xF4, 0xF2, 0x1D]
        case .quickMenu:         return [0x2C]
        case .fullScreen:        return [0xF4, 0x27]
        case .clearLayer:        return [0xF4, 0x2A]
        case .cut:               return [0xF4, 0x1B]
        case .copy:              return [0xF4, 0x06]
        case .paste:             return [0xF4, 0x19]
        case .colorBalance:      return [0xF4, 0x05]
        case .hueSaturation:     return [0xF4, 0x18]
        }
    }

    public static func from(keyCodes: [UInt8]) -> VK01ProcreateAction? {
        allCases.first { $0.keyCodes == keyCodes }
    }
}

// MARK: - Unified Dial Action

public enum DialAction: Hashable, Codable, Sendable {
    case shortcut(modifiers: VK01Modifiers, keyCode: UInt8)
    case macro(steps: [VK01MacroStep])
    case multimedia(VK01MediaKey)
    case mouse(VK01MouseAction)
    case procreate(VK01ProcreateAction)

    public var categoryName: String {
        switch self {
        case .shortcut: return "Keyboard Shortcut"
        case .macro: return "Multi-Key Macro"
        case .multimedia: return "Media & System"
        case .mouse: return "Mouse & Scroll"
        case .procreate: return "Procreate"
        }
    }

    public var summary: String {
        switch self {
        case let .shortcut(modifiers, keyCode):
            let keyLabel = VK01Key.byCode[keyCode]?.label ?? String(format: "0x%02X", keyCode)
            let modNames = modifiers.readableNames
            if modNames.isEmpty {
                return keyLabel
            }
            return (modNames + [keyLabel]).joined(separator: " + ")
        case let .macro(steps):
            if steps.isEmpty { return "Empty Macro" }
            if steps.count == 1 && steps[0].delayMs == 0 {
                return DialAction.shortcut(modifiers: steps[0].modifiers, keyCode: steps[0].keyCode).summary
            }
            return steps.map(\.displayString).joined(separator: " → ")
        case let .multimedia(media):
            return media.title
        case let .mouse(mouse):
            return mouse.title
        case let .procreate(procreate):
            return procreate.title
        }
    }
}

// MARK: - Lighting Configuration

public struct VK01LightConfig: Hashable, Codable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var brightness: UInt8 // 0..100
    public var isOn: Bool

    public init(red: UInt8 = 0, green: UInt8 = 180, blue: UInt8 = 255, brightness: UInt8 = 80, isOn: Bool = true) {
        self.red = red
        self.green = green
        self.blue = blue
        self.brightness = min(brightness, 100)
        self.isOn = isOn
    }
}

// MARK: - Complete Device Configuration State

public struct VK01DeviceConfig: Hashable, Codable, Sendable {
    public var slots: [DialSlot: DialAction]
    public var light: VK01LightConfig

    public init(
        slots: [DialSlot: DialAction] = [
            .turnLeft: DialSlot.turnLeft.factoryDefaultAction,
            .turnRight: DialSlot.turnRight.factoryDefaultAction,
            .click: DialSlot.click.factoryDefaultAction,
            .clickAndTurnLeft: DialSlot.clickAndTurnLeft.factoryDefaultAction,
            .clickAndTurnRight: DialSlot.clickAndTurnRight.factoryDefaultAction
        ],
        light: VK01LightConfig = VK01LightConfig()
    ) {
        self.slots = slots
        self.light = light
    }
}

// MARK: - Packet Builder & Parser

public enum VK01Protocol {
    public static let usbPacketSize = 65
    public static let blePacketSize = 64

    /// Builds the 65-byte Commit / Release / Keepalive packet (`03 FD FE FF 00...`)
    public static func buildCommitPacket(size: Int = usbPacketSize) -> [UInt8] {
        var packet = [UInt8](repeating: 0x00, count: max(size, 64))
        packet[0] = 0x03
        packet[1] = 0xFD
        packet[2] = 0xFE
        packet[3] = 0xFF
        return packet
    }

    /// Builds the 65-byte Read Device Configuration packet (`03 FF FF FF...`)
    public static func buildReadConfigPacket(size: Int = usbPacketSize) -> [UInt8] {
        var packet = [UInt8](repeating: 0xFF, count: max(size, 64))
        packet[0] = 0x03
        return packet
    }

    /// Builds the 65-byte Lighting Control packet (`03 FD 00 06 R G B brightness isOn 00...`)
    public static func buildLightPacket(_ config: VK01LightConfig, size: Int = usbPacketSize) -> [UInt8] {
        var packet = [UInt8](repeating: 0x00, count: max(size, 64))
        packet[0] = 0x03
        packet[1] = 0xFD
        packet[2] = 0x00
        packet[3] = 0x06
        packet[4] = config.red
        packet[5] = config.green
        packet[6] = config.blue
        packet[7] = min(config.brightness, 100)
        packet[8] = config.isOn ? 0x01 : 0x00
        return packet
    }

    /// Builds the 3 64/65-byte LED Effect Mode packets (`03 FE B0 <step 0..2> <mode 0..5>`)
    public static func buildLEDModePackets(mode: UInt8, size: Int = usbPacketSize) -> [[UInt8]] {
        let clampedMode = min(mode, 5)
        return (0..<3).map { step in
            var packet = [UInt8](repeating: 0x00, count: max(size, 64))
            packet[0] = 0x03
            packet[1] = 0xFE
            packet[2] = 0xB0
            packet[3] = UInt8(step)
            packet[4] = clampedMode
            return packet
        }
    }

    /// Builds a single 65-byte configuration packet for a given command byte and `DialAction`
    public static func buildActionPacket(commandCode: UInt8, action: DialAction, size: Int = usbPacketSize) -> [UInt8] {
        var packet = [UInt8](repeating: 0x00, count: max(size, 64))
        packet[0] = 0x03
        packet[1] = 0xFD
        packet[2] = commandCode
        packet[3] = 0x01

        switch action {
        case let .shortcut(modifiers, keyCode):
            let step = VK01MacroStep(modifiers: modifiers, keyCode: keyCode, delayMs: 0)
            encodeMacroSteps([step], into: &packet)

        case let .macro(steps):
            encodeMacroSteps(steps, into: &packet)

        case let .multimedia(mediaKey):
            packet[4] = 0x02 // Type 0x02 = Multimedia
            packet[5] = 0x00
            let flags = mediaKey.packetFlags
            packet[6] = flags.subcount
            packet[7] = 0x00
            packet[8] = 0x00
            let usage = mediaKey.consumerUsage
            packet[9]  = UInt8(usage & 0xFF)
            packet[10] = UInt8((usage >> 8) & 0xFF)
            packet[11] = 0x00
            packet[12] = flags.extFlag

        case let .mouse(mouseAction):
            packet[4] = 0x03 // Type 0x03 = Mouse / Scroll / Gesture
            switch mouseAction {
            case .leftClick:
                packet[5] = 0x01; packet[6] = 0x04; packet[12] = 0x01
            case .rightClick:
                packet[5] = 0x01; packet[6] = 0x04; packet[12] = 0x02
            case .middleClick:
                packet[5] = 0x01; packet[6] = 0x04; packet[12] = 0x04
            case .scrollUp:
                packet[5] = 0x01; packet[6] = 0x04; packet[9] = 0x00; packet[21] = 0x01
            case .scrollDown:
                packet[5] = 0x01; packet[6] = 0x04; packet[9] = 0x00; packet[21] = 0xFF
            case .ctrlScrollUp:
                packet[5] = 0x01; packet[6] = 0x04; packet[9] = 0xF1; packet[21] = 0x01
            case .ctrlScrollDown:
                packet[5] = 0x01; packet[6] = 0x04; packet[9] = 0xF1; packet[21] = 0xFF
            case .shiftScrollUp:
                packet[5] = 0x01; packet[6] = 0x04; packet[9] = 0xF2; packet[21] = 0x01
            case .shiftScrollDown:
                packet[5] = 0x01; packet[6] = 0x04; packet[9] = 0xF2; packet[21] = 0xFF
            case .optScrollUp:
                packet[5] = 0x01; packet[6] = 0x04; packet[9] = 0xF3; packet[21] = 0x01
            case .optScrollDown:
                packet[5] = 0x01; packet[6] = 0x04; packet[9] = 0xF3; packet[21] = 0xFF
            case .swipeLeft:
                packet[5] = 0x04; packet[6] = 0x04; packet[9] = 0x01
            case .swipeRight:
                packet[5] = 0x04; packet[6] = 0x04; packet[9] = 0x02
            case .swipeUp:
                packet[5] = 0x04; packet[6] = 0x04; packet[9] = 0x03
            case .swipeDown:
                packet[5] = 0x04; packet[6] = 0x04; packet[9] = 0x04
            case .likeDoubleTap:
                packet[5] = 0x04; packet[6] = 0x04; packet[9] = 0x05
            }

        case let .procreate(procreateAction):
            packet[4] = 0x04 // Type 0x04 = Procreate
            packet[5] = 0x00
            let codes = procreateAction.keyCodes
            packet[6] = UInt8(min(codes.count, 19))
            var offset = 7
            for code in codes.prefix(19) {
                packet[offset] = 0x00
                packet[offset + 1] = 0x00
                packet[offset + 2] = code
                offset += 3
            }
        }

        return packet
    }

    private static func encodeMacroSteps(_ steps: [VK01MacroStep], into packet: inout [UInt8]) {
        packet[4] = 0x01 // Type 0x01 = Standard Key / Macro
        packet[5] = 0x00

        // Flatten modifier prefix keys (delay = 0) + keyCode (delay = step.delayMs)
        var rawEntries: [(delayMs: UInt16, keyCode: UInt8)] = []
        for step in steps {
            for modCode in step.modifiers.prefixKeyCodes {
                if rawEntries.count < 19 {
                    rawEntries.append((delayMs: 0, keyCode: modCode))
                }
            }
            if rawEntries.count < 19 {
                let clampedDelay = min(step.delayMs, 60000)
                rawEntries.append((delayMs: clampedDelay, keyCode: step.keyCode))
            }
        }

        packet[6] = UInt8(rawEntries.count)
        var offset = 7
        for entry in rawEntries {
            packet[offset]     = UInt8((entry.delayMs >> 8) & 0xFF) // Big-Endian high byte
            packet[offset + 1] = UInt8(entry.delayMs & 0xFF)        // Big-Endian low byte
            packet[offset + 2] = entry.keyCode
            offset += 3
        }
    }

    /// Builds the full sequence of packets needed to program a slot:
    /// 1. Primary command packet (`03 FD <primary_cmd> ...`)
    /// 2. Optional legacy command packet (`03 FD <legacy_cmd> ...`)
    /// 3. Commit / Release packet (`03 FD FE FF 00...`)
    public static func buildSlotProgrammingSequence(
        slot: DialSlot,
        action: DialAction,
        includeLegacyCommand: Bool = true,
        size: Int = usbPacketSize
    ) -> [[UInt8]] {
        var sequence: [[UInt8]] = []
        sequence.append(buildActionPacket(commandCode: slot.primaryCommandCode, action: action, size: size))
        if includeLegacyCommand {
            sequence.append(buildActionPacket(commandCode: slot.legacyCommandCode, action: action, size: size))
        }
        sequence.append(buildCommitPacket(size: size))
        return sequence
    }

    // MARK: - Packet Normalization & Parsing

    public enum ParsedPacket: Sendable {
        case slotConfig(DialSlot, DialAction)
        case lightConfig(VK01LightConfig)
        case commitOrEnd
        case unknown([UInt8])
    }

    /// Normalizes a raw received USB/BLE packet (strips duplicate leading `0x03` report ID if present)
    public static func normalizeReceivedPacket(_ raw: [UInt8]) -> [UInt8] {
        if raw.count >= 4 && raw[0] == 0x03 && raw[1] == 0x03 && raw[2] == 0xFD {
            return Array(raw.dropFirst())
        }
        return raw
    }

    public static func isConfigEndPacket(_ raw: [UInt8]) -> Bool {
        let pkt = normalizeReceivedPacket(raw)
        return pkt.count >= 4 && pkt[0] == 0x03 && pkt[1] == 0xFD && pkt[2] == 0xFE && pkt[3] == 0xFF
    }

    /// Decodes a configuration response packet from the VK-01 (`applyReadConfigPacket` at `0x100055ea0`)
    public static func parsePacket(_ raw: [UInt8]) -> ParsedPacket {
        let pkt = normalizeReceivedPacket(raw)
        guard pkt.count >= 9, pkt[0] == 0x03, pkt[1] == 0xFD else {
            return .unknown(raw)
        }

        let cmd = pkt[2]
        if cmd == 0xFE && pkt[3] == 0xFF {
            return .commitOrEnd
        }

        // Lighting config packet: `03 FD 00 06 R G B brightness isOn`
        if cmd == 0x00 {
            let light = VK01LightConfig(
                red: pkt[4],
                green: pkt[5],
                blue: pkt[6],
                brightness: min(pkt[7], 100),
                isOn: pkt[8] != 0
            )
            return .lightConfig(light)
        }

        guard let slot = DialSlot.from(commandCode: cmd) else {
            return .unknown(raw)
        }

        let keyType = pkt[4]
        switch keyType {
        case 0x01:
            // Standard Key / Macro (`applyStandardKeyConfigPacket` at `0x100056010`)
            let count = Int(min(pkt[6], 19))
            guard count > 0 else { return .unknown(raw) }
            var steps: [VK01MacroStep] = []
            var pendingModifiers = VK01Modifiers()

            for i in 0..<count {
                let base = 7 + (i * 3)
                guard base + 2 < pkt.count else { break }
                let delayMs = (UInt16(pkt[base]) << 8) | UInt16(pkt[base + 1])
                let code = pkt[base + 2]
                guard code != 0 else { continue }

                if let mod = VK01Modifiers.from(prefixKeyCode: code), i < count - 1 {
                    pendingModifiers.insert(mod)
                } else {
                    steps.append(VK01MacroStep(modifiers: pendingModifiers, keyCode: code, delayMs: delayMs))
                    pendingModifiers = []
                }
            }

            if !pendingModifiers.isEmpty, let lastModCode = pendingModifiers.prefixKeyCodes.last {
                steps.append(VK01MacroStep(modifiers: [], keyCode: lastModCode, delayMs: 0))
            }

            if steps.count == 1 && steps[0].delayMs == 0 {
                return .slotConfig(slot, .shortcut(modifiers: steps[0].modifiers, keyCode: steps[0].keyCode))
            } else if !steps.isEmpty {
                return .slotConfig(slot, .macro(steps: steps))
            }
            return .unknown(raw)

        case 0x02:
            // Multimedia (`applyMultimediaConfigPacket` at `0x100056df0`)
            guard pkt.count >= 11 else { return .unknown(raw) }
            let usage = UInt16(pkt[9]) | (UInt16(pkt[10]) << 8)
            if let mediaKey = VK01MediaKey.from(consumerUsage: usage) {
                return .slotConfig(slot, .multimedia(mediaKey))
            }
            return .unknown(raw)

        case 0x03:
            // Mouse / Scroll / Swipe (`applyMouseConfigPacket` at `0x1000571e0`)
            guard pkt.count >= 22 else { return .unknown(raw) }
            let subType = pkt[5]
            if subType == 0x04 && pkt[6] == 0x04 {
                switch pkt[9] {
                case 0x01: return .slotConfig(slot, .mouse(.swipeLeft))
                case 0x02: return .slotConfig(slot, .mouse(.swipeRight))
                case 0x03: return .slotConfig(slot, .mouse(.swipeUp))
                case 0x04: return .slotConfig(slot, .mouse(.swipeDown))
                case 0x05: return .slotConfig(slot, .mouse(.likeDoubleTap))
                default: break
                }
            } else if subType == 0x01 && pkt[6] == 0x04 {
                let wheel = pkt[21]
                let mod = pkt[9]
                if wheel == 0x01 {
                    switch mod {
                    case 0xF1: return .slotConfig(slot, .mouse(.ctrlScrollUp))
                    case 0xF2: return .slotConfig(slot, .mouse(.shiftScrollUp))
                    case 0xF3: return .slotConfig(slot, .mouse(.optScrollUp))
                    default:   return .slotConfig(slot, .mouse(.scrollUp))
                    }
                } else if wheel == 0xFF {
                    switch mod {
                    case 0xF1: return .slotConfig(slot, .mouse(.ctrlScrollDown))
                    case 0xF2: return .slotConfig(slot, .mouse(.shiftScrollDown))
                    case 0xF3: return .slotConfig(slot, .mouse(.optScrollDown))
                    default:   return .slotConfig(slot, .mouse(.scrollDown))
                    }
                }
                switch pkt[12] {
                case 0x01: return .slotConfig(slot, .mouse(.leftClick))
                case 0x02: return .slotConfig(slot, .mouse(.rightClick))
                case 0x04: return .slotConfig(slot, .mouse(.middleClick))
                default: break
                }
            }
            return .unknown(raw)

        case 0x04:
            // Procreate (`applyProcreateConfigPacket` at `0x1000575c0`)
            let count = Int(min(pkt[6], 19))
            var codes: [UInt8] = []
            for i in 0..<count {
                let base = 7 + (i * 3)
                guard base + 2 < pkt.count else { break }
                let code = pkt[base + 2]
                if code != 0 { codes.append(code) }
            }
            if let procreate = VK01ProcreateAction.from(keyCodes: codes) {
                return .slotConfig(slot, .procreate(procreate))
            }
            // Fallback to shortcut/macro if custom codes were stored in type 0x04
            var mods = VK01Modifiers()
            let mainKey: UInt8 = codes.last ?? 0
            for c in codes.dropLast() {
                if let m = VK01Modifiers.from(prefixKeyCode: c) {
                    mods.insert(m)
                }
            }
            if mainKey != 0 {
                return .slotConfig(slot, .shortcut(modifiers: mods, keyCode: mainKey))
            }
            return .unknown(raw)

        default:
            return .unknown(raw)
        }
    }

    public static func hexString(_ bytes: [UInt8], maxBytes: Int = 28) -> String {
        let slice = bytes.prefix(maxBytes)
        let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
        if bytes.count > maxBytes {
            return "\(hex) … (\(bytes.count)B)"
        }
        return "\(hex) (\(bytes.count)B)"
    }
}
