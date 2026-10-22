import BLEKit
import Foundation

/// GATT layout of Canon EOS and PowerShot bodies (protocol reference § Bluetooth protocol
/// reference › Canon). Every UUID shares the base
/// `xxxxxxxx-0000-1000-0000-D8492FFFA821`. A body holds one Bluetooth
/// function at a time: a wireless remote (we emulate a BR-E1) or a smartphone.
public enum Canon {
    public static func uuid(_ short: UInt32) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-1000-0000-D8492FFFA821", short))!
    }

    private static func chr(_ service: UInt32, _ characteristic: UInt32) -> GATTCharacteristicID {
        GATTCharacteristicID(service: uuid(service), characteristic: uuid(characteristic))
    }

    // MARK: Remote (BR-E1)

    /// Advertised while the camera pairs a wireless remote.
    public static let remoteService = uuid(0x0005_0000)
    /// `0x03` + our name.
    public static let remoteIdentify = chr(0x0005_0000, 0x0005_0002)
    /// One control byte: mode | buttons.
    public static let remoteControl = chr(0x0005_0000, 0x0005_0003)

    public enum Control {
        /// Immediate mode, no buttons: every button up.
        public static let idle = Data([0x0C])
        public static let focus = Data([0x4C])
        public static let shutter = Data([0x8C])
    }

    // MARK: Smartphone

    /// Advertised while the camera pairs a smartphone.
    public static let smartService = uuid(0x0001_0000)
    /// Pairing answer indications (`0x02` accept, `0x03` reject) and `0x01` + name.
    public static let smartName = chr(0x0001_0000, 0x0001_0006)
    /// `0x03` + our UUID, `0x04` + name, `0x05` + platform, then `0x01`.
    public static let smartIdentity = chr(0x0001_0000, 0x0001_000A)
    public static let shootingService = uuid(0x0003_0000)
    public static let mode = chr(0x0003_0000, 0x0003_0010)
    public static let shutter = chr(0x0003_0000, 0x0003_0030)
    /// Trigger state notifications (CanonBLEIntervalometer); the candidate shutter ack.
    public static let triggerState = chr(0x0003_0000, 0x0003_0031)
    public static let locationService = uuid(0x0004_0000)
    /// `0x01` enables; then 20-byte location packets.
    public static let location = chr(0x0004_0000, 0x0004_0002)
    /// `0x03` = the camera asks us to enable, `0x02` = enabled.
    public static let locationIndication = chr(0x0004_0000, 0x0004_0003)

    public static let pairAccepted: UInt8 = 0x02
    public static let pairRejected: UInt8 = 0x03
    /// Platform byte: `0x01` iOS, `0x02` Android (furble sends `0x02`).
    public static let platformIOS: UInt8 = 0x01
    /// furble's "shoot" mode; CanonBLEIntervalometer writes `0x03`. The
    /// device test pass (Phase 6) decides between them.
    public static let shootMode: UInt8 = 0x02
    public static let locationRequest: UInt8 = 0x03
    public static let locationEnabled: UInt8 = 0x02

    public enum Trigger {
        public static let press = Data([0x00, 0x01])
        /// "Finish the trigger and get the result".
        public static let release = Data([0x00, 0x02])
    }

    /// The smartphone location packet (little-endian floats, as furble sends):
    /// `0x04`, `N`/`S`, |latitude|, `E`/`W`, |longitude|, `+`/`-`, |elevation|,
    /// Unix time.
    public static func locationPacket(_ fix: GeoFix, time: Date) -> Data {
        var p: [UInt8] = [0x04]
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { p.append(contentsOf: $0) }
        }
        func put(_ value: Float) { put(value.bitPattern) }
        let altitude = fix.altitude ?? 0
        p.append(fix.latitude < 0 ? UInt8(ascii: "S") : UInt8(ascii: "N"))
        put(Float(abs(fix.latitude)))
        p.append(fix.longitude < 0 ? UInt8(ascii: "W") : UInt8(ascii: "E"))
        put(Float(abs(fix.longitude)))
        p.append(altitude < 0 ? UInt8(ascii: "-") : UInt8(ascii: "+"))
        put(Float(abs(altitude)))
        put(UInt32(clamping: Int64(time.timeIntervalSince1970.rounded(.down))))
        return Data(p)
    }
}

/// Canon "Remote" mode: the camera pairs us as a BR-E1. One-way by design,
/// so every shot is a timed press reported as *assumed*. The camera reacts
/// only in a self-timer/remote drive mode, which the pairing steps say.
public actor CanonRemoteDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "canon.remote",
        brand: .canon,
        displayName: "Canon (Remote)",
        capabilities: [.halfPress, .bulb],
        ackSource: "none (one-way protocol)"
    )

    public static var serviceUUIDs: [UUID] { [Canon.remoteService] }

    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        guard advertisement.serviceUUIDs.contains(Canon.remoteService) else { return nil }
        return CameraMatch(driverID: descriptor.id, displayName: advertisement.localName ?? "Canon",
                           modelCode: nil, isPairable: true, details: ["function": "remote"])
    }

    static let pressHold: Duration = .milliseconds(100)
    static let focusSettle: Duration = .milliseconds(250)

    private let link: DriverLink

    public init(transport: any GATTTransport) {
        link = DriverLink(transport: transport, adaptiveWrites: true)
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        link.events.stream()
    }

    static let script: ShotScript = {
        let focus = ShotStep.write(ShotWrite(Canon.Control.focus, to: Canon.remoteControl, withResponse: false))
        let full = ShotStep.write(ShotWrite(Canon.Control.shutter, to: Canon.remoteControl, withResponse: false,
                                            firesShutter: true))
        let idle = ShotStep.write(ShotWrite(Canon.Control.idle, to: Canon.remoteControl, withResponse: false))
        let shot: [ShotStep] = [full, .hold(pressHold), idle]
        return ShotScript(focusSupported: true, focusPress: [focus], focusRelease: [idle],
                          shootFromFocus: shot, shootWithoutFocus: shot, latch: [full], unlatch: [idle],
                          releaseAll: [idle], minimumWriteGap: .zero,
                          acknowledgesFocus: false, focusSettle: focusSettle)
    }()

    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        progress(.bonding)
        try await identify(client, window: DriverLink.bondingWindow)
        progress(.done)
        return .bondOnly
    }

    /// furble identifies on every connect.
    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        try await identify(client, window: DriverLink.writeTimeout)
    }

    public func disconnect() async {
        for write in Self.script.releaseAllWrites { try? await send(write) }
        await link.disconnect()
    }

    private func identify(_ client: ClientIdentity, window: Duration) async throws {
        try await link.discover([Canon.remoteService], required: [Canon.remoteIdentify, Canon.remoteControl])
        // The protected write raises the system pairing dialog (Just Works).
        try await link.write(Data([0x03]) + Data(client.name.utf8), to: Canon.remoteIdentify, timeout: window)
    }

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        switch button {
        case .focus: try await send(ShotWrite(Canon.Control.focus, to: Canon.remoteControl, withResponse: false))
        case .shutter:
            try await send(ShotWrite(Canon.Control.shutter, to: Canon.remoteControl, withResponse: false,
                                     firesShutter: true))
        case .movie: return .unsupported
        }
        return .sent
    }

    public func release(_ button: CameraButton) async throws {
        guard button != .movie else { return }
        try await send(ShotWrite(Canon.Control.idle, to: Canon.remoteControl, withResponse: false))
    }

    public func send(_ write: ShotWrite) async throws {
        try await link.send(write)
    }
}

/// Canon "Smartphone" mode: the camera pairs us as Camera Connect. The user
/// accepts on the camera; then shutter (no half-press) and location. The
/// trigger-state notifications are logged; until the device test pass
/// decodes them, shots are timed presses reported as *assumed*.
public actor CanonSmartDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "canon.smart",
        brand: .canon,
        displayName: "Canon (Smartphone)",
        capabilities: [.bulb, .geotag, .backgroundShooting],
        ackSource: "00030031 notify (undecoded; timed press)"
    )

    public static var serviceUUIDs: [UUID] { [Canon.smartService, Canon.locationService] }

    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        guard advertisement.serviceUUIDs.contains(Canon.smartService) else { return nil }
        return CameraMatch(driverID: descriptor.id, displayName: advertisement.localName ?? "Canon",
                           modelCode: nil, isPairable: true, details: ["function": "smartphone"])
    }

    static let pressHold: Duration = .milliseconds(100)
    /// The camera shows Accept / Cancel for about a minute.
    static let answerWindow: Duration = .seconds(60)
    private let link: DriverLink
    /// How long `startLocationLink` waits for the camera's "enabled".
    private let enableWindow: Duration
    private var usesRemote = true
    private var locationActive = false
    private var locationEnabled = false

    public init(transport: any GATTTransport) {
        self.init(transport: transport, enableWindow: .seconds(5))
    }

    init(transport: any GATTTransport, enableWindow: Duration) {
        link = DriverLink(transport: transport, adaptiveWrites: true)
        self.enableWindow = enableWindow
    }

    public func setFeatures(remote: Bool, geotag: Bool) {
        usesRemote = remote
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        link.events.stream()
    }

    static let script: ShotScript = {
        let press = ShotStep.write(ShotWrite(Canon.Trigger.press, to: Canon.shutter, firesShutter: true))
        let release = ShotStep.write(ShotWrite(Canon.Trigger.release, to: Canon.shutter))
        return ShotScript(focusSupported: false, focusPress: [], focusRelease: [], shootFromFocus: [],
                          shootWithoutFocus: [press, .hold(pressHold), release],
                          latch: [press], unlatch: [release], releaseAll: [release],
                          minimumWriteGap: .zero, acknowledgesFocus: false)
    }()

    // MARK: Pairing and reconnect

    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        try await discover()
        progress(.bonding)
        // Subscribing touches a protected descriptor: the system dialog, then
        // the camera's own Accept prompt after our identification.
        let answers = try await link.inbox(Canon.smartName, timeout: DriverLink.bondingWindow)
        progress(.registering)
        try await identify(client)
        while true {
            let answer = try await answerOrRejected(answers)
            if answer.first == Canon.pairAccepted { break }
            if answer.first == Canon.pairRejected { throw CameraError.pairingRejected }
        }
        try await finishConnect()
        progress(.done)
        return .bondOnly
    }

    /// furble repeats the identification on every connect and, once bonded,
    /// takes acceptance for granted.
    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        try await discover()
        try await identify(client)
        try await finishConnect()
    }

    public func disconnect() async {
        // `00 02` ends a trigger a lost link or a failed write left held.
        for write in Self.script.releaseAllWrites { try? await send(write) }
        locationActive = false
        await link.disconnect()
    }

    private func discover() async throws {
        var required = [Canon.smartName, Canon.smartIdentity]
        required.append(usesRemote ? Canon.shutter : Canon.location)
        try await link.discover([Canon.smartService, Canon.shootingService, Canon.locationService], required: required)
    }

    private func identify(_ client: ClientIdentity) async throws {
        let name = Data(client.name.utf8)
        let uuid = withUnsafeBytes(of: client.uuid.uuid) { Data($0) }
        try await link.write(Data([0x01]) + name, to: Canon.smartName)
        try await link.write(Data([0x03]) + uuid, to: Canon.smartIdentity)
        try await link.write(Data([0x04]) + name, to: Canon.smartIdentity)
        try await link.write(Data([0x05, Canon.platformIOS]), to: Canon.smartIdentity)
    }

    private func answerOrRejected(_ answers: NotificationInbox) async throws -> Data {
        do {
            return try await answers.next(timeout: Self.answerWindow)
        } catch CameraError.transport(.timeout) {
            throw CameraError.pairingRejected
        }
    }

    /// Location indications, the final identity write, shoot mode, trigger state.
    private func finishConnect() async throws {
        locationEnabled = false
        if await link.has(Canon.locationIndication) {
            try await link.subscribe(Canon.locationIndication, handler: { [weak self] value in
                await self?.locationIndicated(value)
            })
        }
        try await link.write(Data([0x01]), to: Canon.smartIdentity)
        if await link.has(Canon.mode) {
            try await link.write(Data([Canon.shootMode]), to: Canon.mode)
        }
        if await link.has(Canon.triggerState) {
            try? await link.subscribe(Canon.triggerState, decode: { .captureStatus($0) })
        }
    }

    private func locationIndicated(_ value: Data) async {
        switch value.first {
        case Canon.locationRequest?:
            try? await link.write(Data([0x01]), to: Canon.location)
        case Canon.locationEnabled?:
            locationEnabled = true
            link.events.yield(.locationEnabled(true))
        default:
            link.events.yield(.unknown(characteristic: Canon.locationIndication, value: value))
        }
    }

    // MARK: Location (push)

    public func startLocationLink() async throws -> LocationLinkMode {
        guard await link.has(Canon.location) else { throw CameraError.unsupported }
        locationActive = true
        // The camera says "enabled" after its request is answered; packets
        // before that are ignored, so give it a moment.
        let deadline = ContinuousClock.now.advanced(by: enableWindow)
        while !locationEnabled, ContinuousClock.now < deadline {
            // Throws when cancelled instead of spinning until the deadline.
            try await Task.sleep(for: .milliseconds(100))
        }
        return .push
    }

    public func stopLocationLink() async {
        locationActive = false
    }

    /// Throws `locationLinkOff` until the camera says location is enabled
    /// (*GPS device settings › Select GPS device › Smartphone*).
    public func updateLocation(_ fix: GeoFix, time: Date, zone: TimeZone) async throws {
        guard locationActive else { throw CameraError.unsupported }
        guard locationEnabled else { throw CameraError.locationLinkOff }
        try await link.send(ShotWrite(Canon.locationPacket(fix, time: time), to: Canon.location))
    }

    // MARK: Buttons

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        guard button == .shutter else { return .unsupported }
        try await send(ShotWrite(Canon.Trigger.press, to: Canon.shutter, firesShutter: true))
        return .sent
    }

    public func release(_ button: CameraButton) async throws {
        guard button == .shutter else { return }
        try await send(ShotWrite(Canon.Trigger.release, to: Canon.shutter))
    }

    public func send(_ write: ShotWrite) async throws {
        try await link.send(write)
    }
}
