import SwiftUI
import AppKit
import VK01Core

@main
struct VK01ProgrammerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = VK01DeviceManager()
    @StateObject private var uiState = ProgrammerUIState()

    var body: some Scene {
        WindowGroup("Anticater VK-01 Programmer") {
            MainProgrammerView(manager: manager, ui: uiState)
                .frame(minWidth: 1020, minHeight: 720)
                .onAppear {
                    manager.connectAuto()
                }
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - UI State ViewModel (ObservableObject avoids CommandLineTools @State macro dependency)

@MainActor
final class ProgrammerUIState: ObservableObject {
    enum EditorTab: String, CaseIterable, Identifiable {
        case shortcut   = "Keyboard Shortcut"
        case media      = "Media & System"
        case mouse      = "Mouse & Scroll"
        case macro      = "Multi-Key Macro"
        case procreate  = "Procreate"

        var id: String { rawValue }
    }

    @Published var selectedSlot: DialSlot = .turnLeft
    @Published var editorTab: EditorTab = .shortcut
    @Published var showPacketLog: Bool = true

    // Shortcut editor state
    @Published var shortcutMods: VK01Modifiers = []
    @Published var shortcutKeyCode: UInt8 = 0x04 // A
    @Published var isRecordingKey: Bool = false

    // Macro editor state
    @Published var macroSteps: [VK01MacroStep] = [
        VK01MacroStep(modifiers: [.leftCommand], keyCode: 0x06, delayMs: 0),
        VK01MacroStep(modifiers: [.leftCommand], keyCode: 0x19, delayMs: 50)
    ]
    @Published var newStepMods: VK01Modifiers = []
    @Published var newStepKeyCode: UInt8 = 0x04
    @Published var newStepDelayMs: Int = 50

    // Lighting color picker state
    @Published var lightColor: Color = Color(red: 0, green: 180.0 / 255.0, blue: 1.0)

    private var eventMonitor: Any?

    func toggleKeyRecording(onCaptured: @escaping (VK01Modifiers, UInt8) -> Void) {
        if isRecordingKey {
            stopKeyRecording()
        } else {
            isRecordingKey = true
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                if event.keyCode == 0x35 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    self.stopKeyRecording()
                    return nil
                }
                if let hidCode = VK01Key.from(macOSVirtualKeyCode: event.keyCode) {
                    var mods = VK01Modifiers()
                    if event.modifierFlags.contains(.command) { mods.insert(.leftCommand) }
                    if event.modifierFlags.contains(.control) { mods.insert(.leftControl) }
                    if event.modifierFlags.contains(.option)  { mods.insert(.leftOption) }
                    if event.modifierFlags.contains(.shift)   { mods.insert(.leftShift) }
                    if event.modifierFlags.contains(.function) && hidCode < 0x3A { mods.insert(.fn) }

                    onCaptured(mods, hidCode)
                    self.stopKeyRecording()
                    return nil
                }
                return event
            }
        }
    }

    func stopKeyRecording() {
        isRecordingKey = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Main Programmer View

struct MainProgrammerView: View {
    @ObservedObject var manager: VK01DeviceManager
    @ObservedObject var ui: ProgrammerUIState

    var body: some View {
        VStack(spacing: 0) {
            headerToolbar
            Divider()

            HSplitView {
                leftDialAndLightColumn
                    .frame(minWidth: 400, idealWidth: 430, maxWidth: 480)

                rightActionEditorColumn
                    .frame(minWidth: 560, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if ui.showPacketLog {
                Divider()
                packetLogDrawer
                    .frame(height: 165)
            }
        }
        .onChange(of: ui.selectedSlot) { newSlot in
            syncEditorStateFromSlot(newSlot)
        }
        .onAppear {
            syncEditorStateFromSlot(ui.selectedSlot)
        }
    }

    // MARK: - Top Header Toolbar

    private var headerToolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 11, height: 11)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Anticater VK-01 Dial Programmer")
                            .font(.headline)
                        Text(manager.connectionMode.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(connectionStatusColor.opacity(0.18))
                            .foregroundColor(connectionStatusColor)
                            .clipShape(Capsule())
                        if let battery = manager.batteryLevel {
                            Label("\(battery)%", systemImage: "battery.100")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(manager.statusBanner)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                manager.connectAuto()
            } label: {
                Label("Auto (USB/BLE)", systemImage: "cable.connector")
            }

            Button {
                manager.connectBLE()
            } label: {
                Label("Bluetooth LE", systemImage: "antenna.radiowaves.left.and.right")
            }

            Button {
                Task { await manager.readConfigurationFromDevice() }
            } label: {
                Label("Read from Dial", systemImage: "arrow.down.circle")
            }
            .disabled(manager.connectionMode == .disconnected || manager.isBusy)

            Button {
                Task { await manager.programAllSlots() }
            } label: {
                Label("Program All 5 Inputs", systemImage: "bolt.horizontal.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.connectionMode == .disconnected || manager.isBusy)

            Button {
                Task { await manager.resetToFactoryDefaults() }
            } label: {
                Label("Factory Reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(manager.isBusy)

            Toggle(isOn: $ui.showPacketLog) {
                Image(systemName: "terminal")
            }
            .toggleStyle(.button)
            .help("Toggle Raw Packet Inspector")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var connectionStatusColor: Color {
        switch manager.connectionMode {
        case .usb: return .green
        case .bluetooth: return .blue
        case .disconnected: return .orange
        }
    }

    // MARK: - Left Column: Interactive 5-Input Dial Map & RGB Lighting

    private var leftDialAndLightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dialVisualSection
                lightingSection
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
    }

    private var dialVisualSection: some View {
        GroupBox {
            VStack(spacing: 14) {
                HStack {
                    Label("5 Programmable Dial Inputs", systemImage: "dial.medium.fill")
                        .font(.headline)
                    Spacer()
                    Text("Click any input to configure")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Top Row: Turn Left (CCW) & Turn Right (CW)
                HStack(spacing: 12) {
                    slotCard(.turnLeft)
                    slotCard(.turnRight)
                }

                // Center: Physical Dial Ring + Center Click Button
                ZStack {
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [.cyan.opacity(0.6), .blue.opacity(0.8), .purple.opacity(0.6), .cyan.opacity(0.6)],
                                center: .center
                            ),
                            lineWidth: 6
                        )
                        .frame(width: 170, height: 170)
                        .background(Circle().fill(Color(NSColor.controlBackgroundColor)))

                    slotCard(.click)
                        .frame(width: 148)
                }
                .padding(.vertical, 4)

                // Bottom Row: Click + Turn Left & Click + Turn Right
                HStack(spacing: 12) {
                    slotCard(.clickAndTurnLeft)
                    slotCard(.clickAndTurnRight)
                }
            }
            .padding(8)
        }
    }

    private func slotCard(_ slot: DialSlot) -> some View {
        let isSelected = (ui.selectedSlot == slot)
        let action = manager.config.slots[slot] ?? slot.factoryDefaultAction

        return Button {
            ui.selectedSlot = slot
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: slot.systemSymbolName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isSelected ? .white : .accentColor)
                    Text(slot.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isSelected ? .white : .primary)
                    Spacer()
                    Text(String(format: "0x%02X", slot.primaryCommandCode))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                }

                Text(action.summary)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isSelected ? .white.opacity(0.95) : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var lightingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("RGB Ring Lighting", systemImage: "lightbulb.led.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("Light On", isOn: $manager.config.light.isOn)
                        .toggleStyle(.switch)
                        .onChange(of: manager.config.light.isOn) { _ in
                            Task { await manager.applyLighting() }
                        }
                }

                HStack(spacing: 12) {
                    ColorPicker("Color", selection: $ui.lightColor, supportsOpacity: false)
                        .onChange(of: ui.lightColor) { newColor in
                            if let rgb = NSColor(newColor).usingColorSpace(.sRGB) {
                                manager.config.light.red = UInt8(clamping: Int(round(rgb.redComponent * 255)))
                                manager.config.light.green = UInt8(clamping: Int(round(rgb.greenComponent * 255)))
                                manager.config.light.blue = UInt8(clamping: Int(round(rgb.blueComponent * 255)))
                            }
                        }

                    Spacer()

                    // Quick Color Swatches
                    ForEach([
                        (0, 180, 255, "Cyan"),
                        (255, 60, 60, "Red"),
                        (50, 220, 100, "Green"),
                        (160, 80, 255, "Purple"),
                        (255, 180, 0, "Amber"),
                        (255, 255, 255, "White")
                    ], id: \.3) { r, g, b, name in
                        Button {
                            manager.config.light.red = UInt8(r)
                            manager.config.light.green = UInt8(g)
                            manager.config.light.blue = UInt8(b)
                            ui.lightColor = Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
                            Task { await manager.applyLighting() }
                        } label: {
                            Circle()
                                .fill(Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }

                HStack {
                    Text("Brightness: \(manager.config.light.brightness)%")
                        .font(.caption)
                        .frame(width: 105, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(manager.config.light.brightness) },
                            set: { manager.config.light.brightness = UInt8(clamping: Int($0)) }
                        ),
                        in: 0...100,
                        step: 5
                    )
                    Button("Apply Light") {
                        Task { await manager.applyLighting() }
                    }
                    .disabled(manager.connectionMode == .disconnected)
                }

                HStack(spacing: 6) {
                    Text("LED Effect:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(0..<6, id: \.self) { mode in
                        Button("Mode \(mode + 1)") {
                            Task { await manager.applyLEDMode(UInt8(mode)) }
                        }
                        .controlSize(.small)
                        .disabled(manager.connectionMode == .disconnected)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Right Column: Selected Slot Action Editor

    private var rightActionEditorColumn: some View {
        let slot = ui.selectedSlot
        let currentAction = manager.config.slots[slot] ?? slot.factoryDefaultAction
        let previewPacket = VK01Protocol.buildActionPacket(
            commandCode: slot.primaryCommandCode,
            action: currentAction
        )

        return VStack(alignment: .leading, spacing: 14) {
            // Selected Slot Header
            HStack(alignment: .center) {
                Image(systemName: slot.systemSymbolName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(slot.title)
                            .font(.title3.weight(.bold))
                        Text(slot.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text("Assigned Action:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentAction.summary)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button {
                    Task {
                        _ = await manager.programSlot(slot, action: slot.factoryDefaultAction)
                        syncEditorStateFromSlot(slot)
                    }
                } label: {
                    Label("Default (\(slot.factoryDefaultAction.summary))", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Category Picker
            Picker("Action Category", selection: $ui.editorTab) {
                ForEach(ProgrammerUIState.EditorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            // Tab Body
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch ui.editorTab {
                    case .shortcut:
                        shortcutEditorView
                    case .media:
                        mediaEditorView
                    case .mouse:
                        mouseEditorView
                    case .macro:
                        macroEditorView
                    case .procreate:
                        procreateEditorView
                    }
                }
                .padding(16)
            }

            Divider()

            // Bottom Packet Preview + Program Button
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HID / GATT Packet Preview (cmd \(String(format: "0x%02X / 0x%02X", slot.primaryCommandCode, slot.legacyCommandCode))):")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(VK01Protocol.hexString(previewPacket, maxBytes: 22))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                }

                Spacer()

                Toggle("Send Legacy Code (\(String(format: "0x%02X", slot.legacyCommandCode)))", isOn: $manager.includeLegacyCommands)
                    .font(.caption)
                    .toggleStyle(.checkbox)

                Button {
                    Task {
                        _ = await manager.programSlot(slot, action: currentAction)
                    }
                } label: {
                    Label("Program \"\(slot.title)\" to Dial", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }

    // MARK: - Tab 1: Keyboard Shortcut Editor

    private var shortcutEditorView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("1. Record or Pick Key Combination") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            ui.toggleKeyRecording { mods, code in
                                ui.shortcutMods = mods
                                ui.shortcutKeyCode = code
                                applyShortcutSelection()
                            }
                        } label: {
                            Label(
                                ui.isRecordingKey ? "Press any key combo… (Esc to cancel)" : "Record Key Combo",
                                systemImage: ui.isRecordingKey ? "record.circle.fill" : "keyboard"
                            )
                            .foregroundColor(ui.isRecordingKey ? .red : .primary)
                        }

                        Text("or select modifiers & key below:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Modifier toggles
                    HStack(spacing: 14) {
                        modifierToggle("⌘ Command", flag: .leftCommand)
                        modifierToggle("⌃ Control", flag: .leftControl)
                        modifierToggle("⌥ Option", flag: .leftOption)
                        modifierToggle("⇧ Shift", flag: .leftShift)
                        modifierToggle("fn", flag: .fn)
                    }

                    HStack(spacing: 12) {
                        Text("Key:")
                            .font(.subheadline.weight(.medium))
                        Picker("Key", selection: $ui.shortcutKeyCode) {
                            ForEach(VK01Key.allKeys) { key in
                                Text("\(key.label) (\(key.category))").tag(key.code)
                            }
                        }
                        .frame(maxWidth: 280)
                        .onChange(of: ui.shortcutKeyCode) { _ in
                            applyShortcutSelection()
                        }

                        Button("Set Shortcut") {
                            applyShortcutSelection()
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("2. Popular macOS & Creative App Shortcuts") {
                let presets: [(String, VK01Modifiers, UInt8)] = [
                    ("⌘Z Undo", [.leftCommand], 0x1D),
                    ("⇧⌘Z Redo", [.leftCommand, .leftShift], 0x1D),
                    ("⌘C Copy", [.leftCommand], 0x06),
                    ("⌘V Paste", [.leftCommand], 0x19),
                    ("⌘X Cut", [.leftCommand], 0x1B),
                    ("⌘S Save", [.leftCommand], 0x16),
                    ("⌘+ Zoom In", [.leftCommand], 0x2E),
                    ("⌘- Zoom Out", [.leftCommand], 0x2D),
                    ("⌘0 Actual Size", [.leftCommand], 0x27),
                    ("[ Brush Smaller", [], 0x2F),
                    ("] Brush Larger", [], 0x30),
                    ("← Left Arrow", [], 0x50),
                    ("→ Right Arrow", [], 0x4F),
                    ("↑ Up Arrow", [], 0x52),
                    ("↓ Down Arrow", [], 0x51),
                    ("Space (Play/Pause)", [], 0x2C),
                    ("⌃← Prev Space", [.leftControl], 0x50),
                    ("⌃→ Next Space", [.leftControl], 0x4F)
                ]

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], spacing: 8) {
                    ForEach(presets, id: \.0) { title, mods, code in
                        Button {
                            ui.shortcutMods = mods
                            ui.shortcutKeyCode = code
                            applyShortcutSelection()
                        } label: {
                            Text(title)
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
            }
        }
    }

    private func modifierToggle(_ label: String, flag: VK01Modifiers) -> some View {
        Toggle(
            label,
            isOn: Binding(
                get: { ui.shortcutMods.contains(flag) },
                set: { isOn in
                    if isOn { ui.shortcutMods.insert(flag) } else { ui.shortcutMods.remove(flag) }
                    applyShortcutSelection()
                }
            )
        )
        .toggleStyle(.checkbox)
    }

    private func applyShortcutSelection() {
        manager.config.slots[ui.selectedSlot] = .shortcut(modifiers: ui.shortcutMods, keyCode: ui.shortcutKeyCode)
    }

    // MARK: - Tab 2: Multimedia & System Keys

    private var mediaEditorView: some View {
        GroupBox("Select Multimedia or System Control") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 195), spacing: 10)], spacing: 10) {
                ForEach(VK01MediaKey.allCases) { media in
                    let isCurrent = (manager.config.slots[ui.selectedSlot] == .multimedia(media))
                    Button {
                        manager.config.slots[ui.selectedSlot] = .multimedia(media)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: media.systemSymbolName)
                                .frame(width: 20)
                                .foregroundColor(isCurrent ? .white : .accentColor)
                            Text(media.title)
                                .font(.caption.weight(.medium))
                                .foregroundColor(isCurrent ? .white : .primary)
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isCurrent ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Tab 3: Mouse, Scroll & Gestures

    private var mouseEditorView: some View {
        GroupBox("Select Mouse Click, Scroll Wheel, or Swipe Gesture") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(VK01MouseAction.allCases) { mouseAction in
                    let isCurrent = (manager.config.slots[ui.selectedSlot] == .mouse(mouseAction))
                    Button {
                        manager.config.slots[ui.selectedSlot] = .mouse(mouseAction)
                    } label: {
                        HStack {
                            Image(systemName: "computermouse.fill")
                                .foregroundColor(isCurrent ? .white : .accentColor)
                            Text(mouseAction.title)
                                .font(.caption.weight(.medium))
                                .foregroundColor(isCurrent ? .white : .primary)
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isCurrent ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Tab 4: Multi-Key Macro Sequence Editor

    private var macroEditorView: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Add Step to Macro Sequence (Up to 19 Entries)") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Toggle("⌘", isOn: Binding(
                            get: { ui.newStepMods.contains(.leftCommand) },
                            set: { if $0 { ui.newStepMods.insert(.leftCommand) } else { ui.newStepMods.remove(.leftCommand) } }
                        ))
                        Toggle("⌃", isOn: Binding(
                            get: { ui.newStepMods.contains(.leftControl) },
                            set: { if $0 { ui.newStepMods.insert(.leftControl) } else { ui.newStepMods.remove(.leftControl) } }
                        ))
                        Toggle("⌥", isOn: Binding(
                            get: { ui.newStepMods.contains(.leftOption) },
                            set: { if $0 { ui.newStepMods.insert(.leftOption) } else { ui.newStepMods.remove(.leftOption) } }
                        ))
                        Toggle("⇧", isOn: Binding(
                            get: { ui.newStepMods.contains(.leftShift) },
                            set: { if $0 { ui.newStepMods.insert(.leftShift) } else { ui.newStepMods.remove(.leftShift) } }
                        ))

                        Picker("Key", selection: $ui.newStepKeyCode) {
                            ForEach(VK01Key.allKeys) { key in
                                Text(key.label).tag(key.code)
                            }
                        }
                        .frame(width: 140)

                        HStack(spacing: 4) {
                            Text("Delay (ms):")
                                .font(.caption)
                            TextField("ms", value: $ui.newStepDelayMs, format: .number)
                                .frame(width: 65)
                        }

                        Button {
                            let delay = UInt16(clamping: max(0, min(ui.newStepDelayMs, 60000)))
                            ui.macroSteps.append(VK01MacroStep(modifiers: ui.newStepMods, keyCode: ui.newStepKeyCode, delayMs: delay))
                            manager.config.slots[ui.selectedSlot] = .macro(steps: ui.macroSteps)
                        } label: {
                            Label("Add Step", systemImage: "plus.circle.fill")
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Macro Steps (\(ui.macroSteps.count))") {
                VStack(alignment: .leading, spacing: 8) {
                    if ui.macroSteps.isEmpty {
                        Text("No macro steps added yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(ui.macroSteps.enumerated()), id: \.element.id) { idx, step in
                            HStack {
                                Text("Step \(idx + 1):")
                                    .font(.caption.weight(.bold))
                                    .frame(width: 55, alignment: .leading)
                                Text(step.displayString)
                                    .font(.caption.monospaced())
                                Spacer()
                                Button(role: .destructive) {
                                    ui.macroSteps.remove(at: idx)
                                    if !ui.macroSteps.isEmpty {
                                        manager.config.slots[ui.selectedSlot] = .macro(steps: ui.macroSteps)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    HStack {
                        Button("Clear Steps") {
                            ui.macroSteps.removeAll()
                        }
                        Spacer()
                        Button("Use This Macro for \(ui.selectedSlot.title)") {
                            if !ui.macroSteps.isEmpty {
                                manager.config.slots[ui.selectedSlot] = .macro(steps: ui.macroSteps)
                            }
                        }
                        .disabled(ui.macroSteps.isEmpty)
                    }
                    .padding(.top, 4)
                }
                .padding(8)
            }
        }
    }

    // MARK: - Tab 5: Procreate Shortcuts

    private var procreateEditorView: some View {
        GroupBox("Select Procreate Action (Hardware Type 0x04)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 10)], spacing: 10) {
                ForEach(VK01ProcreateAction.allCases) { item in
                    let isCurrent = (manager.config.slots[ui.selectedSlot] == .procreate(item))
                    Button {
                        manager.config.slots[ui.selectedSlot] = .procreate(item)
                    } label: {
                        HStack {
                            Image(systemName: "paintbrush.pointed.fill")
                                .foregroundColor(isCurrent ? .white : .accentColor)
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .foregroundColor(isCurrent ? .white : .primary)
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isCurrent ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Bottom Packet Log Drawer

    private var packetLogDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Hardware Packet Log (USB HID & BLE GATT)", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Clear") {
                    manager.clearLogs()
                }
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(manager.logs) { entry in
                            HStack(spacing: 8) {
                                Text(entry.direction)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(colorForLogDirection(entry.direction))
                                    .frame(width: 34, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .onChange(of: manager.logs.count) { _ in
                    if let last = manager.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func colorForLogDirection(_ dir: String) -> Color {
        switch dir {
        case "TX": return .blue
        case "RX": return .green
        case "ERR": return .red
        case "WARN": return .orange
        default: return .secondary
        }
    }

    private func syncEditorStateFromSlot(_ slot: DialSlot) {
        let action = manager.config.slots[slot] ?? slot.factoryDefaultAction
        switch action {
        case let .shortcut(mods, code):
            ui.editorTab = .shortcut
            ui.shortcutMods = mods
            ui.shortcutKeyCode = code
        case let .macro(steps):
            ui.editorTab = .macro
            ui.macroSteps = steps
        case .multimedia:
            ui.editorTab = .media
        case .mouse:
            ui.editorTab = .mouse
        case .procreate:
            ui.editorTab = .procreate
        }
    }
}
