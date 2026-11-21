import Foundation
import IOKit
import IOKit.hid
@preconcurrency import CoreBluetooth

// MARK: - Transport Types & Log Entry

public enum VK01ConnectionMode: String, Codable, Sendable {
    case disconnected = "Disconnected"
    case usb = "USB-C (HID)"
    case bluetooth = "Bluetooth LE (GATT)"
}

public struct VK01LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let direction: String // "TX", "RX", "INFO", "ERR"
    public let message: String

    public init(direction: String, message: String, timestamp: Date = Date()) {
        self.direction = direction
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - USB HID Transport (IOKit.hid)

public final class VK01USBTransport {
    public static let supportedDevices: [(vid: Int, pid: Int, name: String)] = [
        (0x514C, 0x8850, "Anticater VK-01 (USB)"),
        (0x05AC, 0x022C, "Anticater VK-01 (Alt USB)")
    ]

    private var hidManager: IOHIDManager?
    private var activeDevice: IOHIDDevice?
    private var readThread: Thread?
    private var readRunLoop: CFRunLoop?
    private var shouldStopReadThread: Bool = false
    private let reportBufferPtr: UnsafeMutablePointer<UInt8> = .allocate(capacity: 65)
    private let reportBufferSize = 65
    public var onPacketReceived: (([UInt8]) -> Void)?
    public var onDisconnected: (() -> Void)?
    public var onLog: ((String, String) -> Void)?

    public private(set) var isConnected: Bool = false
    public private(set) var deviceDescription: String = ""

    public init() {
        reportBufferPtr.initialize(repeating: 0, count: reportBufferSize)
    }

    deinit {
        disconnect()
        reportBufferPtr.deallocate()
    }

    public func connect() -> Bool {
        disconnect()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Match vendor usage page 0xFF00 first so macOS never attempts to open the Keyboard (0x01:0x06) interface
        let matchDicts: [[String: Any]] = Self.supportedDevices.map { dev in
            [
                kIOHIDVendorIDKey as String: dev.vid,
                kIOHIDProductIDKey as String: dev.pid,
                kIOHIDPrimaryUsagePageKey as String: 0xFF00
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchDicts as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, false)
        self.hidManager = manager

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !deviceSet.isEmpty else {
            return false
        }

        // Score candidate HID interfaces just like MainLayoutWidget::connectDevice (`0x1000435b0`):
        // Prefer vendor usage_page >= 0xFF00, then non-keyboard/consumer interfaces, then interface 2 or 1.
        struct Candidate {
            let device: IOHIDDevice
            let usagePage: Int
            let usage: Int
            let product: String
            let score: Int
        }

        var candidates: [Candidate] = []
        for dev in deviceSet {
            let usagePage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
            let usage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
            let product = (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String) ?? "VK-01"

            let score: Int
            if usagePage >= 0xFF00 {
                score = 100
            } else if usagePage != 0x01 && usagePage != 0x0C {
                score = 80
            } else if usagePage == 0x0C {
                score = 40
            } else {
                score = 10
            }
            candidates.append(Candidate(device: dev, usagePage: usagePage, usage: usage, product: product, score: score))
        }

        candidates.sort { $0.score > $1.score }

        let probePacket = VK01Protocol.buildCommitPacket(size: VK01Protocol.usbPacketSize)

        for cand in candidates {
            let service = IOHIDDeviceGetService(cand.device)
            guard service != MACH_PORT_NULL,
                  let standaloneDevice = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
                continue
            }

            let ret = IOHIDDeviceOpen(standaloneDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            guard ret == kIOReturnSuccess else {
                onLog?("INFO", String(format: "Skipped USB interface UsagePage=0x%04X Usage=0x%04X (open=0x%08X)", cand.usagePage, cand.usage, ret))
                continue
            }

            // Register input report callback and schedule standalone device on dedicated read thread (matching libhidapi's _read_thread)
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(
                standaloneDevice,
                reportBufferPtr,
                reportBufferSize,
                { context, _, _, _, reportID, report, reportLength in
                    guard let context = context else { return }
                    let transport = Unmanaged<VK01USBTransport>.fromOpaque(context).takeUnretainedValue()
                    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
                    var normalized = bytes
                    if !normalized.isEmpty && normalized[0] != UInt8(reportID & 0xFF) && reportID != 0 {
                        normalized.insert(UInt8(reportID & 0xFF), at: 0)
                    }
                    transport.onLog?("RX", VK01Protocol.hexString(normalized))
                    transport.onPacketReceived?(normalized)
                },
                context
            )

            IOHIDDeviceRegisterRemovalCallback(
                standaloneDevice,
                { context, _, _ in
                    guard let context = context else { return }
                    let transport = Unmanaged<VK01USBTransport>.fromOpaque(context).takeUnretainedValue()
                    transport.isConnected = false
                    transport.onLog?("INFO", "USB-C device unplugged")
                    transport.onDisconnected?()
                },
                context
            )

            shouldStopReadThread = false
            let readySem = DispatchSemaphore(value: 0)
            let thread = Thread { [weak self] in
                guard let self = self, let rl = CFRunLoopGetCurrent() else {
                    readySem.signal()
                    return
                }
                self.readRunLoop = rl
                IOHIDDeviceScheduleWithRunLoop(standaloneDevice, rl, CFRunLoopMode.defaultMode.rawValue)
                readySem.signal()
                while !self.shouldStopReadThread {
                    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
                }
                IOHIDDeviceUnscheduleFromRunLoop(standaloneDevice, rl, CFRunLoopMode.defaultMode.rawValue)
            }
            thread.name = "com.anticater.vk01.usb-read"
            thread.start()
            readySem.wait()
            self.readThread = thread

            // Probe with keepalive packet (`03 FD FE FF 00...`)
            if sendRawPacket(probePacket, on: standaloneDevice, logProbe: true) {
                self.activeDevice = standaloneDevice
                self.isConnected = true
                self.deviceDescription = String(format: "%@ (UsagePage 0x%04X:0x%04X)", cand.product, cand.usagePage, cand.usage)
                onLog?("INFO", "Connected via USB HID: \(self.deviceDescription)")
                return true
            } else {
                shouldStopReadThread = true
                if let rl = readRunLoop { CFRunLoopStop(rl) }
                IOHIDDeviceClose(standaloneDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }

        return false
    }

    public func disconnect() {
        shouldStopReadThread = true
        if let rl = readRunLoop {
            CFRunLoopStop(rl)
            readRunLoop = nil
        }
        readThread = nil
        if let dev = activeDevice {
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            activeDevice = nil
        }
        if let mgr = hidManager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        isConnected = false
        deviceDescription = ""
    }

    @discardableResult
    public func sendPacket(_ packet: [UInt8]) -> Bool {
        guard let dev = activeDevice, isConnected else { return false }
        return sendRawPacket(packet, on: dev, logProbe: false)
    }

    private func sendRawPacket(_ packet: [UInt8], on device: IOHIDDevice, logProbe: Bool) -> Bool {
        // Ensure 65 bytes with Report ID 0x03 at byte 0
        var buf65 = packet
        if buf65.isEmpty || buf65[0] != 0x03 {
            buf65.insert(0x03, at: 0)
        }
        if buf65.count < 65 {
            buf65.append(contentsOf: repeatElement(0x00, count: 65 - buf65.count))
        } else if buf65.count > 65 {
            buf65 = Array(buf65.prefix(65))
        }

        let reportID: CFIndex = 0x03
        // Note: on macOS IOHIDDeviceSetReport, when reportID > 0, passing the buffer starting with reportID (65 bytes)
        // or passing the 64-byte payload after reportID depends on the descriptor. Try 65-byte first (matching hidapi), then 64-byte payload.
        let r1 = buf65.withUnsafeBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, base, buf65.count)
        }
        if r1 == kIOReturnSuccess {
            if !logProbe { onLog?("TX", VK01Protocol.hexString(buf65)) }
            return true
        }

        let payload64 = Array(buf65.dropFirst())
        let r2 = payload64.withUnsafeBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, base, payload64.count)
        }
        if r2 == kIOReturnSuccess {
            if !logProbe { onLog?("TX", VK01Protocol.hexString(buf65)) }
            return true
        }

        if !logProbe {
            onLog?("ERR", String(format: "USB IOHIDDeviceSetReport failed: 65B=0x%08X, 64B=0x%08X", r1, r2))
        }
        return false
    }
}

// MARK: - Bluetooth LE Transport (CoreBluetooth)

public final class VK01BLETransport: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static let serviceAE30 = CBUUID(string: "0000AE30-0000-1000-8000-00805F9B34FB")
    public static let serviceAE40 = CBUUID(string: "0000AE40-0000-1000-8000-00805F9B34FB")
    public static let serviceHID  = CBUUID(string: "00001812-0000-1000-8000-00805F9B34FB")
    public static let serviceBatt = CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")
    public static let serviceInfo = CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB")

    public static let writeCharPriority: [CBUUID] = [
        CBUUID(string: "0000AE41-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "0000AE03-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "0000AE01-0000-1000-8000-00805F9B34FB")
    ]

    public static let notifyCharPriority: [CBUUID] = [
        CBUUID(string: "0000AE42-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "0000AE02-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "0000AE04-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "0000AE05-0000-1000-8000-00805F9B34FB")
    ]

    private static let knownUUIDsStorageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("VK01Programmer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("known_ble_uuids.json")
    }()

    private let bleQueue = DispatchQueue(label: "com.anticater.vk01.ble")
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    public var onPacketReceived: (([UInt8]) -> Void)?
    public var onBatteryLevel: ((Int) -> Void)?
    public var onStateChanged: ((Bool, String) -> Void)?
    public var onLog: ((String, String) -> Void)?

    public private(set) var isReady: Bool = false
    public private(set) var deviceDescription: String = ""
    public private(set) var batteryLevel: Int? = nil

    public override init() {
        super.init()
    }

    public func start() {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            if self.centralManager == nil {
                self.centralManager = CBCentralManager(delegate: self, queue: self.bleQueue)
            } else if self.centralManager?.state == .poweredOn {
                self.scanAndRetrieveConnected()
            } else {
                self.onLog?("INFO", "CoreBluetooth current state: \(self.centralManager?.state.rawValue ?? -1)")
            }
        }
    }

    public func setConfigNotifyEnabled(_ enabled: Bool) {
        bleQueue.async { [weak self] in
            guard let self = self,
                  let peripheral = self.connectedPeripheral,
                  let notifyChar = self.notifyCharacteristic else { return }
            if notifyChar.isNotifying != enabled {
                peripheral.setNotifyValue(enabled, for: notifyChar)
                self.onLog?("INFO", "\(enabled ? "Enabling" : "Disabling") BLE AE42 notifications")
            }
        }
    }

    public func stop() {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            self.centralManager?.stopScan()
            if let p = self.connectedPeripheral {
                if let notifyChar = self.notifyCharacteristic, notifyChar.isNotifying {
                    p.setNotifyValue(false, for: notifyChar)
                }
                self.centralManager?.cancelPeripheralConnection(p)
            }
            self.connectedPeripheral = nil
            self.writeCharacteristic = nil
            self.notifyCharacteristic = nil
            self.isReady = false
            self.deviceDescription = ""
        }
    }

    private func loadKnownUUIDs() -> [UUID] {
        guard let data = try? Data(contentsOf: Self.knownUUIDsStorageURL),
              let strings = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return strings.compactMap(UUID.init(uuidString:))
    }

    private func saveKnownUUID(_ uuid: UUID) {
        var current = loadKnownUUIDs()
        if !current.contains(uuid) {
            current.insert(uuid, at: 0)
            let strings = current.prefix(10).map(\.uuidString)
            if let data = try? JSONEncoder().encode(Array(strings)) {
                try? data.write(to: Self.knownUUIDsStorageURL, options: .atomic)
            }
        }
    }

    public func scanAndRetrieveConnected() {
        guard let central = centralManager, central.state == .poweredOn else { return }

        // 1. Check peripherals already connected to macOS by querying each service UUID individually
        var candidates: [UUID: CBPeripheral] = [:]
        for serviceUUID in [Self.serviceHID, Self.serviceAE30, Self.serviceAE40, Self.serviceBatt, Self.serviceInfo] {
            let list = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
            for p in list {
                candidates[p.identifier] = p
            }
        }

        // 2. Also check cached known VK-01 peripheral UUIDs (macOS often omits system HID devices from retrieveConnectedPeripherals)
        let knownUUIDs = loadKnownUUIDs()
        if !knownUUIDs.isEmpty {
            let retrieved = central.retrievePeripherals(withIdentifiers: knownUUIDs)
            for p in retrieved {
                candidates[p.identifier] = p
            }
        }

        for peripheral in candidates.values {
            let name = peripheral.name ?? ""
            onLog?("INFO", "Found system/cached BLE peripheral: '\(name)' (\(peripheral.identifier)) state=\(peripheral.state.rawValue)")
            if matchesVK01Name(name) || knownUUIDs.contains(peripheral.identifier) {
                connect(to: peripheral)
                return
            }
            discoveredPeripherals[peripheral.identifier] = peripheral
        }

        // 3. Also start active scan for advertising VK-01 peripherals
        onLog?("INFO", "Scanning for VK-01 Bluetooth LE advertisements...")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func matchesVK01Name(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper.contains("VK-01") || upper.contains("VK01") || upper.contains("ANTICATER") || upper.contains("KNOB")
    }

    private func connect(to peripheral: CBPeripheral) {
        centralManager?.stopScan()
        discoveredPeripherals[peripheral.identifier] = peripheral
        connectedPeripheral = peripheral
        peripheral.delegate = self
        onLog?("INFO", "Connecting to BLE peripheral \(peripheral.name ?? peripheral.identifier.uuidString)...")
        centralManager?.connect(peripheral, options: nil)
    }

    @discardableResult
    public func sendPacket(_ packet: [UInt8]) -> Bool {
        guard let peripheral = connectedPeripheral,
              let writeChar = writeCharacteristic,
              isReady else {
            return false
        }

        // BLE packets are 64 bytes (`0x40`) starting with `0x03`
        var buf64 = packet
        if buf64.count == 65 && buf64[0] == 0x03 && buf64[1] == 0x03 {
            buf64.removeFirst()
        } else if buf64.count > 64 {
            buf64 = Array(buf64.prefix(64))
        } else if buf64.count < 64 {
            buf64.append(contentsOf: repeatElement(0x00, count: 64 - buf64.count))
        }

        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse

        bleQueue.async {
            peripheral.writeValue(Data(buf64), for: writeChar, type: writeType)
        }
        onLog?("TX", VK01Protocol.hexString(buf64))
        return true
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            onLog?("INFO", "CoreBluetooth powered on")
            scanAndRetrieveConnected()
        case .poweredOff:
            onLog?("WARN", "Bluetooth is powered off")
            isReady = false
            onStateChanged?(false, "Bluetooth Powered Off")
        case .unauthorized:
            onLog?("ERR", "Bluetooth permission unauthorized for this process")
            isReady = false
            onStateChanged?(false, "Bluetooth Unauthorized")
        case .unsupported:
            onLog?("ERR", "Bluetooth LE unsupported")
            isReady = false
            onStateChanged?(false, "Bluetooth Unsupported")
        default:
            onLog?("INFO", "CoreBluetooth state updated: \(central.state.rawValue)")
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let overflowUUIDs = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
        let allUUIDs = serviceUUIDs + overflowUUIDs
        let hasCustomService = allUUIDs.contains(Self.serviceAE30) || allUUIDs.contains(Self.serviceAE40)
        let hasHIDService = allUUIDs.contains(Self.serviceHID)

        if !advName.isEmpty || hasCustomService || hasHIDService {
            let uuidList = allUUIDs.map(\.uuidString).joined(separator: ",")
            onLog?("INFO", "BLE seen: name='\(advName)' id=\(peripheral.identifier) rssi=\(RSSI) services=[\(uuidList)]")
        }

        if hasCustomService || matchesVK01Name(advName) {
            onLog?("INFO", "Discovered VK-01 over BLE: \(advName.isEmpty ? peripheral.identifier.uuidString : advName) (RSSI \(RSSI))")
            connect(to: peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        saveKnownUUID(peripheral.identifier)
        onLog?("INFO", "BLE connected to \(peripheral.name ?? peripheral.identifier.uuidString); discovering GATT services...")
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onLog?("ERR", "Failed to connect BLE peripheral: \(error?.localizedDescription ?? "unknown error")")
        isReady = false
        onStateChanged?(false, "BLE Connect Failed")
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onLog?("INFO", "BLE peripheral disconnected (will auto-reconnect when awake)")
        isReady = false
        writeCharacteristic = nil
        notifyCharacteristic = nil
        onStateChanged?(false, "Disconnected (Waiting for VK-01)")
        // Request CoreBluetooth background reconnect when peripheral wakes from sleep
        if connectedPeripheral?.identifier == peripheral.identifier {
            central.connect(peripheral, options: nil)
        }
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            onLog?("ERR", "BLE discoverServices error: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }
        let serviceList = services.map { $0.uuid.uuidString }.joined(separator: ", ")
        onLog?("INFO", "BLE services discovered on \(peripheral.name ?? "device"): [\(serviceList)]")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            onLog?("ERR", "BLE discoverCharacteristics error on \(service.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        guard let chars = service.characteristics else { return }
        let charSummary = chars.map { "\($0.uuid.uuidString)(props=0x\(String($0.properties.rawValue, radix: 16)))" }.joined(separator: ", ")
        onLog?("INFO", "Service \(service.uuid.uuidString) chars: [\(charSummary)]")

        // Pick highest-priority write characteristic
        for preferredWrite in Self.writeCharPriority {
            if let match = chars.first(where: { $0.uuid == preferredWrite }) {
                if writeCharacteristic == nil || Self.writeCharPriority.firstIndex(of: match.uuid)! < Self.writeCharPriority.firstIndex(of: writeCharacteristic!.uuid)! {
                    writeCharacteristic = match
                    onLog?("INFO", "Selected BLE Write characteristic: \(match.uuid.uuidString)")
                }
            }
        }

        // Fallback: if no AE41/AE03/AE01 matched yet, check for any writable characteristic in custom service (not 1800/1801/180A/180F)
        let stdServices: Set<String> = ["1800", "1801", "180A", "180F"]
        if writeCharacteristic == nil && !stdServices.contains(service.uuid.uuidString.uppercased()) {
            if let writable = chars.first(where: { $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write) }) {
                writeCharacteristic = writable
                onLog?("INFO", "Selected fallback BLE Write characteristic: \(writable.uuid.uuidString)")
            }
        }

        // Record AE42 for config queries, but keep CCCD notify OFF during normal write sessions
        // (per firmware behavior: leaving AE42 or AE02/AE04/AE05 CCCDs enabled blocks one-shot light/key writes)
        let ae42UUID = CBUUID(string: "0000AE42-0000-1000-8000-00805F9B34FB")
        if let ae42 = chars.first(where: { $0.uuid == ae42UUID }) {
            notifyCharacteristic = ae42
            peripheral.setNotifyValue(false, for: ae42)
        }

        // Also read Battery Level (2A19) or AE10 to wake the firmware's BLE GATT config channel
        for char in chars {
            let uuidStr = char.uuid.uuidString.uppercased()
            if (uuidStr == "2A19" || uuidStr.contains("AE10")) && char.properties.contains(.read) {
                peripheral.readValue(for: char)
            }
        }

        if let writeChar = writeCharacteristic, !isReady {
            bleQueue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, !self.isReady else { return }
                self.isReady = true
                self.saveKnownUUID(peripheral.identifier)
                let name = peripheral.name ?? "VK-01 BLE"
                self.deviceDescription = "\(name) [\(writeChar.uuid.uuidString)]"
                self.onLog?("INFO", "VK-01 BLE GATT ready: \(self.deviceDescription)")
                self.onStateChanged?(true, self.deviceDescription)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            onLog?("WARN", "BLE notify state error for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        } else {
            onLog?("INFO", "BLE CCCD notify enabled for \(characteristic.uuid.uuidString) (isNotifying=\(characteristic.isNotifying))")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        let bytes = [UInt8](data)
        let uuidStr = characteristic.uuid.uuidString.uppercased()
        if uuidStr == "2A19", let battery = bytes.first {
            let pct = Int(battery)
            self.batteryLevel = pct
            onLog?("INFO", "VK-01 Battery Level: \(pct)%")
            onBatteryLevel?(pct)
            return
        }
        onLog?("RX", "\(uuidStr): \(VK01Protocol.hexString(bytes))")
        onPacketReceived?(bytes)
    }
}

// MARK: - Unified Device Manager

@MainActor
public final class VK01DeviceManager: ObservableObject {
    @Published public var connectionMode: VK01ConnectionMode = .disconnected
    @Published public var deviceName: String = "Not Connected"
    @Published public var batteryLevel: Int? = nil
    @Published public var config: VK01DeviceConfig = VK01DeviceConfig()
    @Published public var logs: [VK01LogEntry] = []
    @Published public var isBusy: Bool = false
    @Published public var statusBanner: String = "Connect your VK-01 via USB-C or Bluetooth to begin."
    @Published public var includeLegacyCommands: Bool = true
    private var lastConfigPacketReceivedAt: Date? = nil

    private let usb = VK01USBTransport()
    private let ble = VK01BLETransport()
    private static let configStorageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("VK01Programmer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("device_config.json")
    }()

    public init() {
        loadPersistedConfig()
        setupCallbacks()
    }

    public func savePersistedConfig() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: Self.configStorageURL, options: .atomic)
        }
    }

    public func loadPersistedConfig() {
        if let data = try? Data(contentsOf: Self.configStorageURL),
           let decoded = try? JSONDecoder().decode(VK01DeviceConfig.self, from: data) {
            self.config = decoded
        }
    }

    private func setupCallbacks() {
        usb.onLog = { [weak self] dir, msg in
            Task { @MainActor in
                self?.appendLog(direction: dir, message: msg)
            }
        }
        usb.onPacketReceived = { [weak self] bytes in
            Task { @MainActor in
                self?.handleIncomingPacket(bytes)
            }
        }
        usb.onDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.connectionMode == .usb else { return }
                self.appendLog(direction: "INFO", message: "USB-C unplugged; switching automatically to Bluetooth LE...")
                self.connectBLE()
            }
        }

        ble.onLog = { [weak self] dir, msg in
            Task { @MainActor in
                self?.appendLog(direction: dir, message: msg)
            }
        }
        ble.onPacketReceived = { [weak self] bytes in
            Task { @MainActor in
                self?.handleIncomingPacket(bytes)
            }
        }
        ble.onBatteryLevel = { [weak self] pct in
            Task { @MainActor in
                self?.batteryLevel = pct
            }
        }
        ble.onStateChanged = { [weak self] ready, desc in
            Task { @MainActor in
                guard let self = self else { return }
                if ready {
                    self.connectionMode = .bluetooth
                    self.deviceName = desc
                    self.statusBanner = "Connected over Bluetooth LE (\(desc))."
                } else if self.connectionMode == .bluetooth {
                    self.connectionMode = .disconnected
                    self.deviceName = "Not Connected"
                    self.batteryLevel = nil
                    self.statusBanner = "Bluetooth disconnected."
                }
            }
        }
    }

    public func appendLog(direction: String, message: String) {
        logs.append(VK01LogEntry(direction: direction, message: message))
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    public func clearLogs() {
        logs.removeAll()
    }

    /// Scans for VK-01 first on USB-C, and if not plugged in, starts Bluetooth LE discovery
    public func connectAuto() {
        if usb.connect() {
            connectionMode = .usb
            deviceName = usb.deviceDescription
            statusBanner = "Connected via USB-C: \(usb.deviceDescription)"
            Task {
                await readConfigurationFromDevice()
            }
            return
        }
        connectBLE()
    }

    /// Explicitly connects/scans via Bluetooth LE (even if USB-C is plugged in)
    public func connectBLE() {
        usb.disconnect()
        if connectionMode == .usb {
            connectionMode = .disconnected
            deviceName = "Scanning BLE..."
        }
        statusBanner = "Scanning Bluetooth LE for VK-01..."
        ble.start()
    }

    public func disconnect() {
        usb.disconnect()
        ble.stop()
        connectionMode = .disconnected
        deviceName = "Not Connected"
        statusBanner = "Disconnected."
    }

    private func handleIncomingPacket(_ raw: [UInt8]) {
        let parsed = VK01Protocol.parsePacket(raw)
        switch parsed {
        case let .slotConfig(slot, action):
            lastConfigPacketReceivedAt = Date()
            config.slots[slot] = action
            savePersistedConfig()
            appendLog(direction: "INFO", message: "Loaded [\(slot.title)] = \(action.summary)")
        case let .lightConfig(light):
            lastConfigPacketReceivedAt = Date()
            config.light = light
            savePersistedConfig()
            appendLog(
                direction: "INFO",
                message: "Loaded Lighting: RGB(\(light.red),\(light.green),\(light.blue)) Brightness \(light.brightness)% On=\(light.isOn)"
            )
        case .commitOrEnd:
            lastConfigPacketReceivedAt = Date()
            appendLog(direction: "INFO", message: "Device configuration sync complete (03 FD FE FF)")
            statusBanner = "Device configuration synchronized."
        case .unknown:
            break
        }
    }

    @discardableResult
    public func sendRawPacket(_ packet: [UInt8]) -> Bool {
        switch connectionMode {
        case .usb:
            return usb.sendPacket(packet)
        case .bluetooth:
            return ble.sendPacket(packet)
        case .disconnected:
            appendLog(direction: "ERR", message: "Cannot send packet: VK-01 is not connected")
            return false
        }
    }

    /// Requests the current configuration of all 5 slots + lighting from the device (`03 FF FF ...`)
    public func readConfigurationFromDevice() async {
        guard connectionMode != .disconnected else {
            statusBanner = "Connect VK-01 first to read its configuration."
            return
        }
        isBusy = true
        defer { isBusy = false }

        let size = (connectionMode == .usb) ? VK01Protocol.usbPacketSize : VK01Protocol.blePacketSize
        let req = VK01Protocol.buildReadConfigPacket(size: size)
        let queryStart = Date()

        if connectionMode == .bluetooth {
            ble.setConfigNotifyEnabled(true)
            // Allow 350ms for CoreBluetooth CCCD write before sending config query
            try? await Task.sleep(nanoseconds: 350_000_000)
            for attempt in 1...3 {
                appendLog(direction: "INFO", message: "Requesting BLE device configuration (attempt \(attempt))...")
                _ = sendRawPacket(req)
                for _ in 0..<14 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if let last = lastConfigPacketReceivedAt, last >= queryStart {
                        break
                    }
                }
                if let last = lastConfigPacketReceivedAt, last >= queryStart {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    break
                }
            }
            // Explicitly disable AE42 CCCD after query so subsequent key/light writes are not blocked
            ble.setConfigNotifyEnabled(false)
            try? await Task.sleep(nanoseconds: 150_000_000)
        } else {
            appendLog(direction: "INFO", message: "Requesting device configuration (03 FF FF...)")
            _ = sendRawPacket(req)
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
    }

    /// Programs a single dial input slot on the hardware
    public func programSlot(_ slot: DialSlot, action: DialAction) async -> Bool {
        config.slots[slot] = action
        savePersistedConfig()
        guard connectionMode != .disconnected else {
            statusBanner = "Updated [\(slot.title)] locally (connect VK-01 to write to hardware)."
            return false
        }

        isBusy = true
        defer { isBusy = false }

        let size = (connectionMode == .usb) ? VK01Protocol.usbPacketSize : VK01Protocol.blePacketSize
        let primaryPacket = VK01Protocol.buildActionPacket(commandCode: slot.primaryCommandCode, action: action, size: size)
        let legacyPacket = VK01Protocol.buildActionPacket(commandCode: slot.legacyCommandCode, action: action, size: size)
        let commitPacket = VK01Protocol.buildCommitPacket(size: size)

        appendLog(direction: "INFO", message: "Programming [\(slot.title)] -> \(action.summary)")

        guard sendRawPacket(primaryPacket) else {
            statusBanner = "Failed to write [\(slot.title)] to hardware."
            return false
        }

        if includeLegacyCommands {
            let gapNs: UInt64 = (connectionMode == .bluetooth) ? 60_000_000 : 15_000_000
            try? await Task.sleep(nanoseconds: gapNs)
            _ = sendRawPacket(legacyPacket)
        }

        // Wait 100 ms before sending the commit/release packet (`03 FD FE FF 00...`), matching `sendSelectedKeysToHardware`
        try? await Task.sleep(nanoseconds: 100_000_000)
        let ok = sendRawPacket(commitPacket)
        if ok {
            statusBanner = "Programmed [\(slot.title)] → \(action.summary)"
        }
        return ok
    }

    /// Programs all 5 dial inputs sequentially to hardware
    public func programAllSlots() async -> Bool {
        guard connectionMode != .disconnected else {
            statusBanner = "Connect VK-01 first to write all 5 inputs."
            return false
        }

        for slot in DialSlot.allCases {
            let action = config.slots[slot] ?? slot.factoryDefaultAction
            let ok = await programSlot(slot, action: action)
            if !ok { return false }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        statusBanner = "All 5 dial inputs programmed to VK-01 hardware!"
        return true
    }

    /// Resets all 5 dial inputs to factory defaults and writes them to hardware
    public func resetToFactoryDefaults() async -> Bool {
        for slot in DialSlot.allCases {
            config.slots[slot] = slot.factoryDefaultAction
        }
        savePersistedConfig()
        if connectionMode == .disconnected {
            statusBanner = "Reset all 5 inputs to factory defaults locally."
            return true
        }
        let ok = await programAllSlots()
        if ok {
            statusBanner = "Restored factory defaults to VK-01 hardware."
        }
        return ok
    }

    /// Applies RGB lighting configuration to hardware
    public func applyLighting(_ light: VK01LightConfig? = nil) async -> Bool {
        if let light = light {
            config.light = light
        }
        savePersistedConfig()
        guard connectionMode != .disconnected else {
            statusBanner = "Connect VK-01 first to apply lighting."
            return false
        }
        let size = (connectionMode == .usb) ? VK01Protocol.usbPacketSize : VK01Protocol.blePacketSize
        let pkt = VK01Protocol.buildLightPacket(config.light, size: size)
        let ok = sendRawPacket(pkt)
        if ok {
            statusBanner = "Applied RGB lighting to VK-01."
        }
        return ok
    }

    /// Sends the 3-packet LED Mode sequence (`03 FE B0 step mode`)
    public func applyLEDMode(_ mode: UInt8) async -> Bool {
        guard connectionMode != .disconnected else { return false }
        let size = (connectionMode == .usb) ? VK01Protocol.usbPacketSize : VK01Protocol.blePacketSize
        let packets = VK01Protocol.buildLEDModePackets(mode: mode, size: size)
        for pkt in packets {
            guard sendRawPacket(pkt) else { return false }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        statusBanner = "Applied LED Mode \(mode) to VK-01."
        return true
    }
}
