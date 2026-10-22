import BLEKit
import Foundation

/// GATT layout of Ricoh GR III / IIIx / IV (protocol reference § Bluetooth protocol
/// reference › Ricoh), from furble's `Ricoh.h` and the dm-zharov API doc.
public enum Ricoh {
    private static func chr(_ service: UUID, _ uuid: String) -> GATTCharacteristicID {
        GATTCharacteristicID(service: service, characteristic: UUID(uuidString: uuid)!)
    }

    public static let infoService = UUID(uuidString: "9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1")!
    public static let cameraService = UUID(uuidString: "4B445988-CAA0-4DD3-941D-37B4F52ACA86")!
    public static let shootingService = UUID(uuidString: "9F00F387-8345-4BBC-8B92-B87B52E3091A")!
    public static let bluetoothControlService = UUID(uuidString: "0F291746-0C80-4726-87A7-3C501FD3B4B6")!
    public static let gpsService = UUID(uuidString: "84A0DD62-E8AA-4D0F-91DB-819B6724C69E")!

    public static let modelNumber = chr(infoService, "35FE6272-6AA5-44D9-88E1-F09427F51A71")
    /// 0 off, 1 on, 2 sleep.
    public static let power = chr(cameraService, "B58CE84C-0666-4DE9-BEC8-2D27B27B3211")
    public static let operationMode = chr(cameraService, "1452335A-EC7F-4877-B8AB-0F72E18BB295")
    /// The camera's *Store Location Info.* switch: read, write, notify; 0 or 1.
    public static let geoTag = chr(cameraService, "A36AFDCF-6B67-4046-9BE7-28FB67DBC071")
    /// `[code, parameter]`: code 0 NOP, 1 start, 2 stop; parameter 0 no AF, 1 AF.
    public static let operationRequest = chr(shootingService, "559644B8-E0BC-4011-929B-5CF9199851E7")
    /// 0 immediate, 2 = the camera's 2-s timer.
    public static let shootingFlavour = chr(shootingService, "B29E6DE3-1AEC-48C1-9D05-02CEA57CE664")
    /// Capture status notify; logged until the device test pass decodes it.
    public static let captureStatus = chr(shootingService, "B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA")
    /// AF status notify (running, in focus); logged.
    public static let afStatus = chr(shootingService, "CDFC734E-EA21-427D-A69F-C1A0F7F1E9A3")
    public static let gpsInformation = chr(gpsService, "28F59D60-8B8E-4FCD-A81F-61BDB46595A9")

    public enum Operation {
        public static let immediate = Data([0x00])
        /// Start with AF: a complete shot.
        public static let shootWithAF = Data([0x01, 0x01])
        /// Start without AF, for bulb.
        public static let start = Data([0x01, 0x00])
        public static let stop = Data([0x02, 0x00])
    }

    /// furble's name match, for bodies that advertise no Ricoh service.
    public static func nameMatches(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper == "GR" || ["RICOH", "PENTAX", "GR ", "GRIII", "GR III"].contains { upper.contains($0) }
    }

    /// The 32-byte GPS packet: latitude, longitude and altitude as big-endian
    /// Float64, the year little-endian, month, day, hour, minute, second, then
    /// datum 0 (WGS-84). The time is the fix time, UTC.
    public static func gpsPacket(_ fix: GeoFix, time: Date) -> Data {
        var p: [UInt8] = []
        for value in [fix.latitude, fix.longitude, fix.altitude ?? 0] {
            withUnsafeBytes(of: value.bitPattern.bigEndian) { p.append(contentsOf: $0) }
        }
        let c = utcComponents(time)
        withUnsafeBytes(of: Int16(c.year ?? 2000).littleEndian) { p.append(contentsOf: $0) }
        p += [UInt8(c.month ?? 1), UInt8(c.day ?? 1), UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0)]
        p.append(0x00)
        return Data(p)
    }
}

/// Ricoh GR III / IIIx / IV. A shot is one operation (AF runs inside it; no
/// half-press). Capture and AF status are logged undecoded, so shots are
/// reported as *assumed* until the device test pass confirms their layout.
/// Location is pushed at most every 10 s, stamped with the fix time, and
/// only while the camera's *Store Location Info.* is on.
public actor RicohDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "ricoh",
        brand: .ricoh,
        displayName: "Ricoh GR",
        capabilities: [.geotag, .ackLocation, .backgroundShooting],
        ackSource: "capture status notify (undecoded; timed)"
    )

    public static var serviceUUIDs: [UUID] { [Ricoh.shootingService, Ricoh.gpsService] }

    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        let services = [Ricoh.infoService, Ricoh.cameraService, Ricoh.shootingService, Ricoh.bluetoothControlService]
        let byService = advertisement.serviceUUIDs.contains { services.contains($0) }
        guard byService || advertisement.localName.map(Ricoh.nameMatches) == true else { return nil }
        return CameraMatch(driverID: descriptor.id, displayName: advertisement.localName ?? "Ricoh GR",
                           modelCode: nil, isPairable: true)
    }

    private let link: DriverLink
    private var usesRemote = true
    private var locationActive = false
    /// *Store Location Info.* as last read or notified; `nil` until subscribed
    /// on this connection (a subscribed characteristic cannot be read).
    private var storeLocation: Bool?

    public init(transport: any GATTTransport) {
        link = DriverLink(transport: transport)
    }

    public func setFeatures(remote: Bool, geotag: Bool) {
        usesRemote = remote
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        link.events.stream()
    }

    static let script: ShotScript = {
        let immediate = ShotStep.write(ShotWrite(Ricoh.Operation.immediate, to: Ricoh.shootingFlavour))
        let shoot = ShotStep.write(ShotWrite(Ricoh.Operation.shootWithAF, to: Ricoh.operationRequest,
                                             firesShutter: true))
        let start = ShotStep.write(ShotWrite(Ricoh.Operation.start, to: Ricoh.operationRequest, firesShutter: true))
        let stop = ShotStep.write(ShotWrite(Ricoh.Operation.stop, to: Ricoh.operationRequest))
        // Nothing is held between shots; `stop` ends an operation a lost
        // link or a failed write may have left running.
        return ShotScript(focusSupported: false, focusPress: [], focusRelease: [], shootFromFocus: [],
                          shootWithoutFocus: [immediate, shoot], latch: [immediate, start], unlatch: [stop],
                          releaseAll: [stop], minimumWriteGap: .zero, acknowledgesFocus: false)
    }()

    // MARK: Pairing and reconnect

    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        progress(.bonding)
        try await connect(window: DriverLink.bondingWindow)
        progress(.done)
        return .bondOnly
    }

    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        try await connect(window: DriverLink.writeTimeout)
        if locationActive {
            do {
                _ = try await startLocationLink()
            } catch {
                link.events.yield(.locationEnabled(false))
            }
        }
    }

    public func disconnect() async {
        for write in Self.script.releaseAllWrites { try? await send(write) }
        locationActive = false
        await link.disconnect()
    }

    /// The first protected access raises the passkey on the camera; the
    /// camera rejects every write until the link is bonded.
    private func connect(window: Duration) async throws {
        storeLocation = nil
        try await link.discover([Ricoh.infoService, Ricoh.cameraService, Ricoh.shootingService, Ricoh.gpsService],
                                required: usesRemote ? [Ricoh.operationRequest, Ricoh.shootingFlavour]
                                    : [Ricoh.gpsInformation, Ricoh.geoTag])
        if await link.has(Ricoh.shootingFlavour) {
            try await link.write(Ricoh.Operation.immediate, to: Ricoh.shootingFlavour, timeout: window)
        } else {
            _ = try await link.read(Ricoh.geoTag, timeout: window)
        }
        if await link.has(Ricoh.modelNumber) {
            _ = try? await link.read(Ricoh.modelNumber)
        }
        for chr in [Ricoh.captureStatus, Ricoh.afStatus] {
            guard await link.has(chr) else { continue }
            try? await link.subscribe(chr, decode: { chr == Ricoh.captureStatus ? .captureStatus($0)
                : .unknown(characteristic: chr, value: $0) })
        }
    }

    // MARK: Location (push)

    public nonisolated var geotagRules: GeotagRules {
        GeotagRules(maximumFixAge: .seconds(30), minimumInterval: .seconds(10), stampsSendTime: false)
    }

    /// Reads *Store Location Info.*; throws `locationLinkOff` while it is off.
    /// xGRC never turns it on by itself.
    public func startLocationLink() async throws -> LocationLinkMode {
        guard await link.has(Ricoh.gpsInformation) else { throw CameraError.unsupported }
        if await link.has(Ricoh.geoTag) {
            if storeLocation == nil {
                let enabled = try await link.read(Ricoh.geoTag).first == 0x01
                storeLocation = enabled
                link.events.yield(.locationEnabled(enabled))
                try? await link.subscribe(Ricoh.geoTag, handler: { [weak self] value in
                    await self?.storeLocationChanged(value.first == 0x01)
                })
            }
            guard storeLocation == true else { throw CameraError.locationLinkOff }
        }
        locationActive = true
        return .push
    }

    public func stopLocationLink() async {
        locationActive = false
    }

    private func storeLocationChanged(_ enabled: Bool) {
        storeLocation = enabled
        link.events.yield(.locationEnabled(enabled))
    }

    public func updateLocation(_ fix: GeoFix, time: Date, zone: TimeZone) async throws {
        guard locationActive else { throw CameraError.unsupported }
        guard storeLocation != false else { throw CameraError.locationLinkOff }
        try await link.send(ShotWrite(Ricoh.gpsPacket(fix, time: time), to: Ricoh.gpsInformation))
    }

    // MARK: Buttons

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        guard button == .shutter else { return .unsupported }
        try await link.send([ShotWrite(Ricoh.Operation.immediate, to: Ricoh.shootingFlavour),
                             ShotWrite(Ricoh.Operation.shootWithAF, to: Ricoh.operationRequest, firesShutter: true)])
        return .sent
    }

    public func release(_ button: CameraButton) async throws {}

    public func send(_ write: ShotWrite) async throws {
        try await link.send(write)
    }
}
