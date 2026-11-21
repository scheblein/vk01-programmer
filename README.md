# Anticater VK-01 Programmer for macOS

Native macOS programmer (GUI application + CLI) for the **Anticater VK-01** Bluetooth LE / USB-C rotary dial.

---

## Why the Manufacturer's `ANTICATER.app` Fails on macOS

Reverse engineering `/Applications/ANTICATER.app` (`v2.1.0`) revealed three critical bugs on macOS:
1. **Broken BLE Discovery & Subprocess Lifecycle**:
   - The official app spawns a PyInstaller `ble_helper` subprocess on *every* packet batch (`--send-packets`) and attempts to scan for the dial using `BleakScanner` or match a Windows-style MAC address.
   - On macOS, `CoreBluetooth` hides peripheral MAC addresses behind host-specific `UUID`s, and a VK-01 already connected to macOS as a Bluetooth HID device stops advertising and **only** appears via `CBCentralManager.retrieveConnectedPeripherals(withServices:)`.
   - Worse, disconnecting and reconnecting GATT between Packet 1 (key assignment `03 FD <cmd> ...`) and Packet 2 (commit/release `03 FD FE FF 00...`) causes the dial firmware to drop uncommitted changes.
2. **USB HID Exclusive Access Conflict**:
   - macOS `IOHIDFamily` seizes exclusive access to standard Keyboard (`0x01`) and Consumer Control (`0x0C`) HID interfaces. Opening those interfaces fails with `kIOReturnExclusiveAccess` unless the programmer specifically targets the vendor-defined HID interface (`UsagePage >= 0xFF00`) non-exclusively.
3. **Architecture & Dependencies**:
   - The official app ships as an Intel (`x86_64`) binary bundling an Intel PyInstaller archive, whereas this replacement is built natively for Apple Silicon (`arm64`) using `IOKit.hid`, `CoreBluetooth`, and `SwiftUI`.

---

## Features

- **All 5 Programmable Inputs**:
  1. **Turn Left (CCW)** (`cmd 0x02 / 0x10`)
  2. **Turn Right (CW)** (`cmd 0x04 / 0x12`)
  3. **Click (Center Press)** (`cmd 0x03 / 0x11`)
  4. **Click + Turn Left** (`cmd 0x05 / 0x13`)
  5. **Click + Turn Right** (`cmd 0x06 / 0x15`)
- **All Hardware Action Modes**:
  - **Keyboard Shortcuts**: Any key + modifiers (`⌘ Command`, `⌃ Control`, `⌥ Option`, `⇧ Shift`, `fn`), including live keystroke recording.
  - **Multi-Key Macros**: Sequences of up to 19 key entries with individual per-step millisecond delays (`0–60000 ms`).
  - **Multimedia & System Controls**: Volume Up/Down, Mute, Play/Pause, Next/Previous Track, Stop, Screen Brightness Up/Down, App Launchers & Browser Controls.
  - **Mouse, Scroll Wheel & Gestures**: Left/Right/Middle Click, Scroll Up/Down, `⌃/⇧/⌥ + Scroll` (Zoom / Horizontal Scroll), Swipe Left/Right/Up/Down, and Like (`Double-Tap`).
  - **Procreate Shortcuts**: Hardware Type `0x04` shortcuts (Brush Size `]`/`[`, Fine Brush `⌘]`/`⌘[`, Undo/Redo, QuickMenu, Full Screen, etc.).
- **RGB Ring Lighting**: Live RGB color picker, brightness (`0–100%`), On/Off switch, and 6 LED effect modes.
- **Dual Transport**: Works seamlessly over **USB-C (HID)** and **Bluetooth LE (GATT)**.

---

## Quick Start

### 1. Build the macOS App Bundle & CLI
```sh
./scripts/bundle_app.sh
```
This produces:
- GUI App: `VK01Programmer.app` (launch with `open VK01Programmer.app`)
- CLI Tool: `.build/release/vk01-cli`

### 2. CLI Usage Examples
```sh
# Check connection (USB-C or Bluetooth LE)
.build/release/vk01-cli status

# Read current configuration of all 5 dial inputs + RGB lighting
.build/release/vk01-cli read

# Program Turn Left / Turn Right to Undo / Redo
.build/release/vk01-cli set turn-left cmd+z
.build/release/vk01-cli set turn-right cmd+shift+z

# Program Click to Play/Pause
.build/release/vk01-cli set click play-pause

# Program Click + Turn Left / Right to Zoom Out / Zoom In (Ctrl + Scroll)
.build/release/vk01-cli set click-left ctrl-scroll-down
.build/release/vk01-cli set click-right ctrl-scroll-up

# Program a multi-key macro (Cmd+C followed 50ms later by Cmd+V)
.build/release/vk01-cli set click "macro:cmd+c@0,cmd+v@50"

# Set RGB Ring Lighting (Cyan at 80% brightness)
.build/release/vk01-cli light 0 180 255 80

# Restore Factory Defaults
.build/release/vk01-cli reset
```
