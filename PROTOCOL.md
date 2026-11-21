# Anticater VK-01 Hardware Protocol Specification

Reverse-engineered from `/Applications/ANTICATER.app` (`v2.1.0`, Bundle ID `com.anticater.anticater.en`), including the `x86_64` Mach-O binary (`Contents/MacOS/ANTICATER`) and `Contents/Resources/ble_helper.py`.

---

## 1. Transports & Identifiers

### 1.1 USB HID
- **Primary VID / PID**: `0x514C` / `0x8850`
- **Alternate VID / PID**: `0x05AC` / `0x022C`
- **Target Interface**:
  - Vendor-defined HID interface (`UsagePage >= 0xFF00`, or `UsagePage` not in `{0x01, 0x0C}`, typically interface `1` or `2`).
  - Packet size: **65 bytes** (`0x41`), with byte `0` = Report ID `0x03`, followed by 64 bytes of payload (fallback to 64 bytes if 65-byte write fails).

### 1.2 Bluetooth Low Energy (BLE GATT)
- **Custom Service UUIDs**:
  - Primary Custom Service: `0000AE30-0000-1000-8000-00805F9B34FB`
  - Secondary Custom Service: `0000AE40-0000-1000-8000-00805F9B34FB`
  - Standard BLE HID Service: `00001812-0000-1000-8000-00805F9B34FB`
- **Write Characteristics** (Write Without Response preferred, fallback to Write With Response):
  1. `0000AE41-0000-1000-8000-00805F9B34FB` (primary)
  2. `0000AE03-0000-1000-8000-00805F9B34FB`
  3. `0000AE01-0000-1000-8000-00805F9B34FB`
- **Notify Characteristics**:
  1. `0000AE42-0000-1000-8000-00805F9B34FB` (primary)
  2. `0000AE02-0000-1000-8000-00805F9B34FB`
  3. `0000AE04-0000-1000-8000-00805F9B34FB`
  4. `0000AE05-0000-1000-8000-00805F9B34FB`
- **Packet Size**: **64 bytes** (`0x40`), starting with `0x03`.

---

## 2. The 5 Programmable Dial Inputs

Each of the 5 physical dial inputs maps to a primary command code (`0x02`–`0x06`) and a legacy/compatibility command code (`0x10`–`0x15`). When writing configuration to the device, the official software sends the primary command packet first, followed 10 ms later by a copy using the legacy command code, and finally a Commit/Release packet (`03 FD FE FF 00...`) after 100 ms.

| UI Slot | Input Action | Chinese Label | Primary `cmd` | Legacy `cmd` | Factory Default |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **Index 1** (Top-Left) | **Turn Left (CCW)** | `左上` | `0x02` | `0x10` | Volume Down (`0x00EA`) |
| **Index 2** (Top-Right) | **Turn Right (CW)** | `右上` | `0x04` | `0x12` | Volume Up (`0x00E9`) |
| **Index 3** (Bottom-Left) | **Click & Turn Left** | `左下` | `0x05` | `0x13` | Brightness Down (`0x0070`) |
| **Index 4** (Bottom-Right) | **Click & Turn Right** | `右下` | `0x06` | `0x15` | Brightness Up (`0x006F`) |
| **Index 5** (Center) | **Click (Press)** | `中间` | `0x03` | `0x11` | Mute (`0x00E2`) |

---

## 3. Packet Formats

All packets below are shown as 64/65-byte buffers starting at byte index `0` (`0x03`). All unspecified trailing bytes are `0x00`.

### 3.1 Commit / Release / Keepalive Packet
Sent as a connection probe, as Packet 2 (100 ms after programming an input), and sent by the device as the end-of-config-read marker:
```text
Byte:  00  01  02  03  04 .. 63
Hex:   03  FD  FE  FF  00 .. 00
```

### 3.2 Read Device Configuration Request
```text
Byte:  00  01  02  03 .. 63
Hex:   03  FF  FF  FF .. FF
```
- **Response**: The device sends multiple packets starting with `03 FD <cmd> ...` (or `03 03 FD <cmd> ...` on USB HID when the OS prepends the report ID):
  - `cmd = 0x00`: Lighting configuration (`03 FD 00 06 R G B brightness isOn ...`)
  - `cmd = 0x02..0x06` (or `0x10..0x15`): Key configuration for each of the 5 inputs
  - Terminated by `03 FD FE FF 00 ...`

### 3.3 Type `0x01`: Standard Key / Shortcut / Multi-Key Macro
```text
Byte 00: 0x03
Byte 01: 0xFD
Byte 02: <cmd>          (0x02..0x06 or legacy 0x10..0x15)
Byte 03: 0x01
Byte 04: 0x01           (Type 0x01 = Standard Key / Macro)
Byte 05: 0x00
Byte 06: <count>        (Total number of 3-byte key entries, 1..19, including modifier prefix keys)
Byte 07..: <entries>    (count * 3 bytes)
```
Each 3-byte entry in `<entries>` has the format:
```text
[delay_hi, delay_lo, keycode]
```
- `delay` is an unsigned 16-bit Big-Endian integer in milliseconds (`0`–`60000` ms).
  - Modifier prefix keys always use `delay = 0` (`0x00, 0x00`).
  - First non-modifier key defaults to `0` ms; subsequent keys in a sequence default to `50` ms (`0x00, 0x32`) unless custom delays are specified.
- **Modifier Prefix Keycodes**:
  - `0xF1`: Left Control (`Ctrl`)
  - `0xF2`: Left Shift (`Shift`)
  - `0xF3`: Left Option / Alt (`Alt`)
  - `0xF4`: Left Command / Win (`Command` / `Win`)
  - `0xF5`: Right Control
  - `0xF6`: Right Shift
  - `0xF7`: Right Option / Alt
  - `0xF8`: Right Command / Win
  - `0xF9`: `fn`
- **Standard Keycodes**: Standard USB HID Keyboard/Keypad Page (`0x07`) usage IDs (`0x04`–`0x1D` = `A`–`Z`, `0x1E`–`0x27` = `1`–`0`, `0x28` = `Enter`, `0x29` = `Esc`, `0x2A` = `Backspace`, `0x2B` = `Tab`, `0x2C` = `Space`, `0x3A`–`0x45` = `F1`–`F12`, `0x68`–`0x73` = `F13`–`F24`, `0x4F` = `Right`, `0x50` = `Left`, `0x51` = `Down`, `0x52` = `Up`, etc.).

### 3.4 Type `0x02`: Multimedia / Consumer Control Key
```text
Byte 00: 0x03
Byte 01: 0xFD
Byte 02: <cmd>
Byte 03: 0x01
Byte 04: 0x02           (Type 0x02 = Multimedia / Consumer)
Byte 05: 0x00
Byte 06: <subcount>     (0x01 for standard consumer usages, 0x02 for extended app/browser keys)
Byte 07: 0x00
Byte 08: 0x00
Byte 09: <usage_lo>     (16-bit Little-Endian Consumer Usage ID low byte)
Byte 10: <usage_hi>     (16-bit Little-Endian Consumer Usage ID high byte)
Byte 11: 0x00
Byte 12: <ext_flag>     (0x00 for standard, 0x01 for system apps, 0x02 for browser controls)
```
Supported Consumer Usage IDs:
- `0x00E9`: Volume + (`音量+`, `subcount=1, ext=0`)
- `0x00EA`: Volume - (`音量-`, `subcount=1, ext=0`)
- `0x00E2`: Mute (`静音`, `subcount=1, ext=0`)
- `0x00CD`: Play/Pause (`播放/暂停`, `subcount=1, ext=0`)
- `0x00B5`: Next Track (`下一曲`, `subcount=1, ext=0`)
- `0x00B6`: Previous Track (`上一曲`, `subcount=1, ext=0`)
- `0x00B7`: Stop (`停止`, `subcount=1, ext=0`)
- `0x006F`: Brightness + (`屏幕亮度+`, `subcount=1, ext=0`)
- `0x0070`: Brightness - (`屏幕亮度-`, `subcount=1, ext=0`)
- `0x0152` / `0x0153`: Treble - / + (`subcount=1, ext=0`)
- `0x0154` / `0x0155`: Bass - / + (`subcount=1, ext=0`)
- `0x0183`: Media Player (`subcount=2, ext=1`)
- `0x018A`: Email (`subcount=2, ext=1`)
- `0x0192`: Calculator (`subcount=2, ext=1`)
- `0x0194`: My Computer (`subcount=2, ext=1`)
- `0x0223`: Browser Home (`subcount=2, ext=2`)
- `0x0224`: Browser Back (`subcount=2, ext=2`)
- `0x0225`: Browser Forward (`subcount=2, ext=2`)
- `0x0027`: Browser Refresh (`subcount=2, ext=2`)

### 3.5 Type `0x03`: Mouse Clicks, Scroll Wheel & Gestures
- **Mouse Button Click**:
  ```text
  03 FD <cmd> 01 03 01 04 00 00 00 00 00 <btn> 00...
  ```
  where `<btn>` (Byte 12) = `0x01` (Left Click), `0x02` (Right Click), `0x04` (Middle Click).
- **Mouse Scroll Wheel (with optional modifier)**:
  ```text
  03 FD <cmd> 01 03 01 04 00 00 <mod> 00 00 00 00 00 00 00 00 00 00 00 <dir> 00...
  ```
  where `<mod>` (Byte 9) = `0x00` (None), `0xF1` (Ctrl), `0xF2` (Shift), `0xF3` (Alt/Option), and `<dir>` (Byte 21 / `0x15`) = `0x01` (Scroll Up / `+`) or `0xFF` (Scroll Down / `-`).
- **Swipe / Like Gestures**:
  ```text
  03 FD <cmd> 01 03 04 04 00 00 <gesture> 00...
  ```
  where `<gesture>` (Byte 9) = `0x01` (Swipe Left), `0x02` (Swipe Right), `0x03` (Swipe Up), `0x04` (Swipe Down), `0x05` (Like / Double-Tap).

### 3.6 Type `0x04`: Procreate Shortcuts
```text
03 FD <cmd> 01 04 00 <count> (00 00 <keycode>) * count
```

### 3.7 Lighting Control (`cmd = 0x00, sub = 0x06`)
```text
Byte 00: 0x03
Byte 01: 0xFD
Byte 02: 0x00
Byte 03: 0x06
Byte 04: <R>            (0..255)
Byte 05: <G>            (0..255)
Byte 06: <B>            (0..255)
Byte 07: <brightness>   (0..100)
Byte 08: <isOn>         (0x01 = On, 0x00 = Off)
```

---

## 4. Root Causes of Failure in Official `ANTICATER.app` on macOS

1. **Broken BLE Architecture on macOS**:
   - When connected over Bluetooth, macOS `IOBluetoothHIDDriver` maintains the connection to the VK-01.
   - `ANTICATER.app` spawns a separate PyInstaller `ble_helper` subprocess on *every* command batch (`--send-packets`) and attempts to locate the device via `BleakScanner` using a MAC-like address string or advertisement scan.
   - On macOS, CoreBluetooth does **not** expose peripheral MAC addresses (it uses per-host `UUID` identifiers), and peripherals already connected to macOS system HID do **not** appear in `BleakScanner` advertisement scans unless queried via `CBCentralManager.retrieveConnectedPeripherals(withServices:)`.
   - Furthermore, tearing down and re-establishing GATT connections between Packet 1 (key assignment) and Packet 2 (commit `03 FD FE FF`) causes the firmware to discard uncommitted key writes or drop packets when `m_bleConfigReadInProgress` blocks writes.
2. **USB HID Exclusive Device Seizure on macOS**:
   - Opening the keyboard/consumer HID interface (`UsagePage 0x01` or `0x0C`) on macOS fails with `kIOReturnExclusiveAccess` unless specifically opening the vendor-defined HID interface (`UsagePage >= 0xFF00`) non-exclusively.
