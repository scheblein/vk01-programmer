import Foundation
import VK01Core

// MARK: - CLI Action String Parser

enum CLIActionParser {
    /// Parses user-friendly CLI action strings such as:
    /// - Media: `volume-up`, `volume-down`, `mute`, `play-pause`, `next-track`, `prev-track`, `brightness-up`, `brightness-down`
    /// - Mouse/Scroll: `mouse-left`, `mouse-right`, `mouse-middle`, `scroll-up`, `scroll-down`, `ctrl-scroll-up`, `swipe-left`, `like`
    /// - Procreate: `procreate-undo`, `procreate-redo`, `procreate-brush-up`, `procreate-brush-down`
    /// - Shortcut: `cmd+z`, `ctrl+shift+tab`, `space`, `f5`, `cmd+ opt+left`
    /// - Multi-key Macro: `macro:cmd+c@50,cmd+v@0`
    static func parse(_ input: String) -> DialAction? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if let media = VK01MediaKey(rawValue: lower) {
            return .multimedia(media)
        }
        if let mouse = VK01MouseAction(rawValue: lower) {
            return .mouse(mouse)
        }
        if let procreate = VK01ProcreateAction(rawValue: lower) {
            return .procreate(procreate)
        }

        if lower.hasPrefix("macro:") {
            let body = String(trimmed.dropFirst("macro:".count))
            let stepStrings = body.split(separator: ",").map(String.init)
            var steps: [VK01MacroStep] = []
            for (idx, stepStr) in stepStrings.enumerated() {
                let parts = stepStr.split(separator: "@", maxSplits: 1).map(String.init)
                let comboPart = parts[0]
                let defaultDelay: UInt16 = (idx == 0) ? 0 : 50
                let delayMs = (parts.count > 1 ? UInt16(parts[1]) : nil) ?? defaultDelay
                guard let (mods, keyCode) = parseShortcutCombo(comboPart) else { return nil }
                steps.append(VK01MacroStep(modifiers: mods, keyCode: keyCode, delayMs: delayMs))
            }
            return steps.isEmpty ? nil : .macro(steps: steps)
        }

        if let (mods, keyCode) = parseShortcutCombo(trimmed) {
            return .shortcut(modifiers: mods, keyCode: keyCode)
        }

        return nil
    }

    static func parseShortcutCombo(_ combo: String) -> (VK01Modifiers, UInt8)? {
        let tokens = combo
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "+")
            .map { String($0).lowercased() }
        guard !tokens.isEmpty else { return nil }

        var mods = VK01Modifiers()
        var mainKeyCode: UInt8?

        for (index, token) in tokens.enumerated() {
            let isLast = (index == tokens.count - 1)
            switch token {
            case "cmd", "command", "win", "meta", "super", "lcmd":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF4
                } else {
                    mods.insert(.leftCommand)
                }
            case "rcmd", "rightcommand", "rwin":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF8
                } else {
                    mods.insert(.rightCommand)
                }
            case "ctrl", "control", "lctrl":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF1
                } else {
                    mods.insert(.leftControl)
                }
            case "rctrl", "rightctrl", "rightcontrol":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF5
                } else {
                    mods.insert(.rightControl)
                }
            case "shift", "lshift":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF2
                } else {
                    mods.insert(.leftShift)
                }
            case "rshift", "rightshift":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF6
                } else {
                    mods.insert(.rightShift)
                }
            case "opt", "option", "alt", "lalt":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF3
                } else {
                    mods.insert(.leftOption)
                }
            case "ropt", "rightoption", "ralt", "rightalt":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF7
                } else {
                    mods.insert(.rightOption)
                }
            case "fn":
                if isLast && mainKeyCode == nil && tokens.count == 1 {
                    mainKeyCode = 0xF9
                } else {
                    mods.insert(.fn)
                }
            default:
                if let key = VK01Key.from(label: token) {
                    mainKeyCode = key.code
                } else if token.hasPrefix("0x"), let hex = UInt8(token.dropFirst(2), radix: 16) {
                    mainKeyCode = hex
                } else {
                    return nil
                }
            }
        }

        guard let code = mainKeyCode else { return nil }
        return (mods, code)
    }
}

// MARK: - Protocol Round-Trip Self-Test

func runProtocolSelfTest() -> Bool {
    print("=== VK-01 Protocol Round-Trip Verification ===")
    var allPassed = true

    let testCases: [(DialSlot, DialAction)] = [
        (.turnLeft, .multimedia(.volumeDown)),
        (.turnRight, .multimedia(.volumeUp)),
        (.click, .multimedia(.mute)),
        (.clickAndTurnLeft, .shortcut(modifiers: [.leftCommand], keyCode: 0x1D)), // Cmd + Z
        (.clickAndTurnRight, .shortcut(modifiers: [.leftCommand, .leftShift], keyCode: 0x1D)), // Cmd + Shift + Z
        (.turnLeft, .mouse(.scrollDown)),
        (.turnRight, .mouse(.ctrlScrollUp)),
        (.click, .mouse(.likeDoubleTap)),
        (.clickAndTurnLeft, .procreate(.brushSizeDecrease)),
        (.clickAndTurnRight, .macro(steps: [
            VK01MacroStep(modifiers: [.leftCommand], keyCode: 0x06, delayMs: 0),  // Cmd+C
            VK01MacroStep(modifiers: [.leftCommand], keyCode: 0x19, delayMs: 50)  // Cmd+V (50ms)
        ]))
    ]

    for (slot, action) in testCases {
        let pkt = VK01Protocol.buildActionPacket(commandCode: slot.primaryCommandCode, action: action)
        let parsed = VK01Protocol.parsePacket(pkt)
        switch parsed {
        case let .slotConfig(decodedSlot, decodedAction):
            let ok = (decodedSlot == slot && decodedAction == action)
            print("[\(ok ? "PASS" : "FAIL")] \(slot.title) -> \(action.summary)")
            print("       TX: \(VK01Protocol.hexString(pkt, maxBytes: 24))")
            if !ok {
                print("       Decoded mismatch: \(decodedSlot.title) -> \(decodedAction.summary)")
                allPassed = false
            }
        default:
            print("[FAIL] Failed to decode packet for \(slot.title): \(action.summary)")
            allPassed = false
        }
    }

    let light = VK01LightConfig(red: 12, green: 180, blue: 240, brightness: 75, isOn: true)
    let lightPkt = VK01Protocol.buildLightPacket(light)
    if case let .lightConfig(decodedLight) = VK01Protocol.parsePacket(lightPkt), decodedLight == light {
        print("[PASS] Lighting Packet -> RGB(\(light.red),\(light.green),\(light.blue)) Brightness \(light.brightness)%")
        print("       TX: \(VK01Protocol.hexString(lightPkt, maxBytes: 14))")
    } else {
        print("[FAIL] Lighting Packet round-trip failed")
        allPassed = false
    }

    return allPassed
}

// MARK: - Main Entrypoint

func printUsage() {
    print("""
    Anticater VK-01 Programmer CLI (macOS USB-C & Bluetooth LE)

    Usage:
      vk01-cli status                        Scan & connect to VK-01 via USB-C or BLE
      vk01-cli read                          Read current configuration of all 5 dial inputs
      vk01-cli set <slot> <action>           Program one of the 5 dial inputs
      vk01-cli light <R> <G> <B> [0..100]    Set RGB lighting color & brightness (or 'off')
      vk01-cli reset                         Restore all 5 inputs to factory defaults
      vk01-cli selftest                      Run offline protocol encoding/decoding verification

    Slots (<slot>):
      turn-left        Rotate Counter-Clockwise (CCW)       [cmd 0x02 / 0x10]
      turn-right       Rotate Clockwise (CW)                [cmd 0x04 / 0x12]
      click            Center Press                         [cmd 0x03 / 0x11]
      click-left       Hold Down & Rotate Counter-Clockwise [cmd 0x05 / 0x13]
      click-right      Hold Down & Rotate Clockwise         [cmd 0x06 / 0x15]

    Action Examples (<action>):
      Shortcuts:   cmd+z, cmd+shift+z, ctrl+tab, opt+left, space, return, f12
      Macros:      macro:cmd+c@0,cmd+v@50
      Media:       volume-up, volume-down, mute, play-pause, next-track, prev-track, brightness-up, brightness-down
      Mouse:       mouse-left, mouse-right, scroll-up, scroll-down, ctrl-scroll-up, shift-scroll-down, swipe-left, like
      Procreate:   procreate-brush-up, procreate-brush-down, procreate-undo, procreate-redo, procreate-quickmenu
    """)
}

let rawArgs = Array(CommandLine.arguments.dropFirst())
let forceBLE = rawArgs.contains("--ble")
let args = rawArgs.filter { $0 != "--ble" }
guard let subcommand = args.first?.lowercased() else {
    printUsage()
    exit(0)
}

if subcommand == "selftest" {
    let ok = runProtocolSelfTest()
    exit(ok ? 0 : 1)
}

if subcommand == "help" || subcommand == "--help" || subcommand == "-h" {
    printUsage()
    exit(0)
}

Task { @MainActor in
    let manager = VK01DeviceManager()
    if forceBLE {
        manager.connectBLE()
    } else {
        manager.connectAuto()
    }

    // Wait up to 8.0 seconds if scanning BLE
    if manager.connectionMode == .disconnected {
        for _ in 0..<80 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if manager.connectionMode != .disconnected {
                break
            }
        }
    }

    switch subcommand {
    case "status":
        try? await Task.sleep(nanoseconds: 500_000_000)
        print("Connection Mode: \(manager.connectionMode.rawValue)")
        print("Device:          \(manager.deviceName)")
        print("Status:          \(manager.statusBanner)")
        for log in manager.logs {
            print("  [\(log.direction)] \(log.message)")
        }
        exit(manager.connectionMode == .disconnected ? 1 : 0)

    case "read":
        guard manager.connectionMode != .disconnected else {
            print("Error: VK-01 is not connected over USB-C or Bluetooth LE.")
            exit(1)
        }
        await manager.readConfigurationFromDevice()
        try? await Task.sleep(nanoseconds: 600_000_000)
        print("--- Raw Packet Log ---")
        for log in manager.logs {
            print("  [\(log.direction)] \(log.message)")
        }
        print("=== VK-01 Active Configuration (\(manager.deviceName)) ===")
        for slot in DialSlot.allCases {
            let action = manager.config.slots[slot] ?? slot.factoryDefaultAction
            print(String(format: "  %-18@ : %@", slot.title as NSString, action.summary as NSString))
        }
        let l = manager.config.light
        print("  Lighting           : RGB(\(l.red), \(l.green), \(l.blue)) Brightness \(l.brightness)% (\(l.isOn ? "ON" : "OFF"))")
        exit(0)

    case "set":
        guard args.count >= 3 else {
            print("Usage: vk01-cli set <slot> <action>")
            exit(1)
        }
        guard let slot = DialSlot.from(cliName: args[1]) else {
            print("Error: Unknown slot '\(args[1])'. Valid slots: turn-left, turn-right, click, click-left, click-right")
            exit(1)
        }
        let actionStr = args.dropFirst(2).joined(separator: " ")
        guard let action = CLIActionParser.parse(actionStr) else {
            print("Error: Could not parse action '\(actionStr)'.")
            exit(1)
        }
        let packets = VK01Protocol.buildSlotProgrammingSequence(slot: slot, action: action)
        print("Prepared packets for [\(slot.title)] -> \(action.summary):")
        for (i, pkt) in packets.enumerated() {
            print("  Packet \(i + 1): \(VK01Protocol.hexString(pkt, maxBytes: 24))")
        }
        guard manager.connectionMode != .disconnected else {
            print("Note: VK-01 is not currently connected. Connect via USB-C or Bluetooth to write to hardware.")
            exit(2)
        }
        let ok = await manager.programSlot(slot, action: action)
        try? await Task.sleep(nanoseconds: 300_000_000)
        for log in manager.logs {
            print("  [\(log.direction)] \(log.message)")
        }
        print(ok ? "Successfully programmed [\(slot.title)] on VK-01!" : "Failed to program [\(slot.title)].")
        exit(ok ? 0 : 1)

    case "light":
        if args.count >= 2 && args[1].lowercased() == "off" {
            var light = manager.config.light
            light.isOn = false
            let ok = await manager.applyLighting(light)
            try? await Task.sleep(nanoseconds: 300_000_000)
            print(ok ? "Turned off VK-01 lighting." : "VK-01 not connected.")
            exit(ok ? 0 : 1)
        }
        guard args.count >= 4,
              let r = UInt8(args[1]),
              let g = UInt8(args[2]),
              let b = UInt8(args[3]) else {
            print("Usage: vk01-cli light <R 0..255> <G 0..255> <B 0..255> [brightness 0..100]")
            exit(1)
        }
        let brightness = (args.count >= 5 ? UInt8(args[4]) : nil) ?? 80
        let light = VK01LightConfig(red: r, green: g, blue: b, brightness: brightness, isOn: true)
        let pkt = VK01Protocol.buildLightPacket(light)
        print("Lighting Packet: \(VK01Protocol.hexString(pkt, maxBytes: 14))")
        let ok = await manager.applyLighting(light)
        try? await Task.sleep(nanoseconds: 300_000_000)
        for log in manager.logs {
            print("  [\(log.direction)] \(log.message)")
        }
        print(ok ? "Applied lighting to VK-01." : "VK-01 not connected.")
        exit(ok ? 0 : 1)

    case "reset":
        guard manager.connectionMode != .disconnected else {
            print("Error: Connect VK-01 via USB-C or Bluetooth to reset hardware to factory defaults.")
            exit(1)
        }
        let ok = await manager.resetToFactoryDefaults()
        print(ok ? "Restored VK-01 to factory defaults!" : "Failed to reset VK-01.")
        exit(ok ? 0 : 1)

    default:
        print("Unknown command '\(subcommand)'.")
        printUsage()
        exit(1)
    }
}

RunLoop.main.run()
