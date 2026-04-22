import Flutter
import UIKit
import CoreBluetooth
import AVFoundation
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, CBPeripheralManagerDelegate, CBCentralManagerDelegate {

    // MARK: - BLE Constants
    private let sosServiceUUID    = CBUUID(string: "FFF0")
    private let sosCharUUID       = CBUUID(string: "FFF1")
    private let methodChannelName = "com.example.accident_app/ble_sos"
    private let eventChannelName  = "com.example.accident_app/ble_sos_events"
    private let sosAlertChannelName = "com.example.accident_app/sos_alert"

    // MARK: - SOS Alert
    private var sosAudioPlayer: AVAudioPlayer?
    private var sosVibrateTimer: Timer?
    private var sosToneTimer: Timer?
    private var savedVolume: Float = -1

    // MARK: - BLE Objects
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var pendingAdvertiseResult: FlutterResult?
    private var pendingScanResult: FlutterResult?
    private var eventSink: FlutterEventSink?

    // Payload storage for advertising start
    private var pendingPayload: Data?

    // Dedup
    private var seenDevices = [String: Date]()
    private let dedupWindow: TimeInterval = 60.0

    // MARK: - Flutter engine setup
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        // MethodChannel (BLE)
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: controller.binaryMessenger)
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call: call, result: result)
        }

        // MethodChannel (SOS Alert)
        let sosAlertChannel = FlutterMethodChannel(
            name: sosAlertChannelName,
            binaryMessenger: controller.binaryMessenger)
        sosAlertChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "startSosAlert":
                self?.startSosAlert()
                result(nil)
            case "stopSosAlert":
                self?.stopSosAlert()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // EventChannel (BLE scan results)
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: controller.binaryMessenger)
        eventChannel.setStreamHandler(self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - SOS Alert (iOS)
    private func startSosAlert() {
        // Set audio session to allow playback over silent/DnD
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            savedVolume = session.outputVolume
        } catch {}

        // Play system alarm sound in a loop
        sosVibrateTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        sosToneTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            AudioServicesPlaySystemSound(1005)
        }
        // Run immediately too
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1005)
    }

    private func stopSosAlert() {
        sosVibrateTimer?.invalidate()
        sosVibrateTimer = nil
        sosToneTimer?.invalidate()
        sosToneTimer = nil
        sosAudioPlayer?.stop()
        sosAudioPlayer = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {}
    }

    // MARK: - Method dispatcher
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertising":
            let args = call.arguments as? [String: Any]
            let lat     = args?["lat"]    as? Double
            let lng     = args?["lng"]    as? Double
            let userId  = args?["userId"] as? String ?? "unknown"
            startAdvertising(lat: lat, lng: lng, userId: userId, result: result)

        case "stopAdvertising":
            stopAdvertising()
            result(nil)

        case "startScanning":
            startScanning(result: result)

        case "stopScanning":
            stopScanning()
            result(nil)

        case "isSupported":
            result(CBCentralManager.authorization != .denied)
        case "startMeshScanning":
            startScanning(result: result)
        case "stopMeshScanning":
            stopScanning()
            result(nil)
        case "stopMeshAdvertising":
            stopAdvertising()
            result(nil)
        case "broadcastMeshPayload":
            let args = call.arguments as? [String: Any]
            let fragments = args?["fragments"] as? [String] ?? []
            let intervalMs = args?["intervalMs"] as? Int ?? 140
            let repeatCount = args?["repeatCount"] as? Int ?? 2
            broadcastMeshPayload(fragments: fragments, intervalMs: intervalMs, repeatCount: repeatCount, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func broadcastMeshPayload(
        fragments: [String],
        intervalMs: Int,
        repeatCount: Int,
        result: @escaping FlutterResult
    ) {
        guard !fragments.isEmpty else {
            result(nil)
            return
        }
        let decoded = fragments.compactMap { Data(base64Encoded: $0) }
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<max(1, repeatCount) {
                for fragment in decoded {
                    DispatchQueue.main.sync {
                        self.pendingPayload = fragment
                        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
                    }
                    usleep(useconds_t(max(50, intervalMs) * 1000))
                    DispatchQueue.main.sync {
                        self.stopAdvertising()
                    }
                }
            }
            DispatchQueue.main.async { result(nil) }
        }
    }

    // MARK: - Advertising
    private func startAdvertising(lat: Double?, lng: Double?, userId: String, result: @escaping FlutterResult) {
        pendingAdvertiseResult = result
        pendingPayload = buildPayload(lat: lat, lng: lng, userId: userId)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [
            CBPeripheralManagerOptionRestoreIdentifierKey: "sos-peripheral"
        ])
    }

    private func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager = nil
    }

    // MARK: - Scanning
    private func startScanning(result: @escaping FlutterResult) {
        pendingScanResult = result
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "sos-central"
        ])
    }

    private func stopScanning() {
        centralManager?.stopScan()
        centralManager = nil
    }

    // MARK: - Payload
    private func buildPayload(lat: Double?, lng: Double?, userId: String) -> Data {
        var data = Data(count: 18)
        let hash = UInt64(bitPattern: Int64(userId.hashValue))
        withUnsafeBytes(of: hash) { ptr in
            data.replaceSubrange(0..<8, with: ptr)
        }
        data[8] = 0x01 // SOS flag
        let latF: Float = lat.map { Float($0) } ?? Float.nan
        let lngF: Float = lng.map { Float($0) } ?? Float.nan
        withUnsafeBytes(of: latF.bitPattern.bigEndian) { data.replaceSubrange(9..<13, with: $0) }
        withUnsafeBytes(of: lngF.bitPattern.bigEndian) { data.replaceSubrange(13..<17, with: $0) }
        data[17] = 0x00
        return data
    }

    // MARK: - CBPeripheralManagerDelegate
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        guard let payload = pendingPayload else { return }

        let characteristic = CBMutableCharacteristic(
            type: sosCharUUID,
            properties: [.read, .notify],
            value: payload,
            permissions: .readable)

        let service = CBMutableService(type: sosServiceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let e = error {
            pendingAdvertiseResult?(FlutterError(code: "ADD_SERVICE", message: e.localizedDescription, details: nil))
            pendingAdvertiseResult = nil
            return
        }
        // Advertise the service UUID + service data payload (lat/lng etc.)
        // Service-data advertising is more interoperable for parsing on Android/iOS.
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [sosServiceUUID],
            CBAdvertisementDataLocalNameKey: "SOS_ALERT",
            CBAdvertisementDataServiceDataKey: [
              sosServiceUUID: pendingPayload ?? Data()
            ]
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let e = error {
            pendingAdvertiseResult?(FlutterError(code: "ADVERTISE_FAIL", message: e.localizedDescription, details: nil))
        } else {
            pendingAdvertiseResult?("started")
        }
        pendingAdvertiseResult = nil
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [sosServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        pendingScanResult?("scanning")
        pendingScanResult = nil
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let deviceId = peripheral.identifier.uuidString
        let now = Date()
        if let last = seenDevices[deviceId], now.timeIntervalSince(last) < dedupWindow { return }
        seenDevices[deviceId] = now

        // On iOS the raw payload comes in advertisement data — parse service data for location
        var lat: Double? = nil
        var lng: Double? = nil

        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let data = serviceData[sosServiceUUID], data.count >= 18 {
            let rawPayload = data.base64EncodedString()
            var latBits: UInt32 = 0
            var lngBits: UInt32 = 0
            withUnsafeMutableBytes(of: &latBits) { data.copyBytes(to: $0, from: 9..<13) }
            withUnsafeMutableBytes(of: &lngBits) { data.copyBytes(to: $0, from: 13..<17) }
            let latF = Float(bitPattern: latBits.bigEndian)
            let lngF = Float(bitPattern: lngBits.bigEndian)
            if !latF.isNaN { lat = Double(latF) }
            if !lngF.isNaN { lng = Double(lngF) }
            let event: [String: Any?] = [
                "deviceId": deviceId,
                "lat": lat,
                "lng": lng,
                "rssi": RSSI.intValue,
                "rawPayload": rawPayload
            ]
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(event)
            }
            return
        }
        let event: [String: Any?] = ["deviceId": deviceId, "lat": lat, "lng": lng, "rssi": RSSI.intValue]
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }
}

// MARK: - FlutterStreamHandler (EventChannel)
extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
