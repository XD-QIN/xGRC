import BLEKit
import Foundation

/// GATT layout of Nikon bodies (protocol reference § Bluetooth protocol reference ›
/// Nikon). One service; characteristics share its base
/// `0000xxxx-3DD4-4255-8D62-6DC7B9BD5561`. Only the "Connection to remote"
/// function (ML-L7 emulation) is supported; SnapBridge needs a Classic
/// Bluetooth bond iOS does not offer third-party apps.
public enum Nikon {
    public static let companyID: UInt16 = 0x0399

    public static func uuid(_ short: UInt16) -> UUID {
        UUID(uuidString: String(format: "0000%04X-3DD4-4255-8D62-6DC7B9BD5561", short))!
    }

    private static func chr(_ short: UInt16) -> GATTCharacteristicID {
        GATTCharacteristicID(service: service, characteristic: uuid(short))
    }

    public static let service = uuid(0xDE00)
    /// Remote indications, logged undecoded (the candidate shutter ack).
    public static let remoteIndication = chr(0x2084)
    /// The 17-byte stage messages, write and indicate.
    public static let remotePairing = chr(0x2087)
    /// `mode, command`: `02 02` press, `02 00` release.
    public static let remoteShutter = chr(0x2083)
    /// SnapBridge pairing: present when the camera is set to pair a smart device.
    public static let smartPairing = chr(0x2000)

    public enum Shutter {
        public static let press = Data([0x02, 0x02])
        public static let release = Data([0x02, 0x00])
    }

    /// Each camera answer must arrive within this.
    public static let stageTimeout: Duration = .seconds(10)

    /// Our 8-byte identity: a 4-byte device ID, sent back in the camera's
    /// advertisement once paired, then a 4-byte nonce. The device ID's first
    /// byte is always `0x01` in remote mode.
    public static func makeID() -> Data {
        var id = (0..<8).map { _ in UInt8.random(in: 0...255) }
        id[0] = 0x01
        return Data(id)
    }

    /// Stage 1: `01`, timestamp `00 00 00 00 00 00 00 01`, our ID.
    public static func stage1(id: Data) -> Data {
        Data([0x01, 0, 0, 0, 0, 0, 0, 0, 0x01]) + id
    }

    /// The camera's stage 2 in remote mode: all zero after the stage byte.
    public static let stage2 = Data([0x02] + [UInt8](repeating: 0, count: 16))
    public static let stage3 = Data([0x03] + [UInt8](repeating: 0, count: 16))

    /// The camera serial from its stage 4 (`04`, zero timestamp, 8 ASCII
    /// characters), or `nil` when the message is not a stage 4.
    public static func serial(fromStage4 message: Data) -> String? {
        let b = [UInt8](message)
        guard b.count == 17, b[0] == 0x04, b[1..<9].allSatisfy({ $0 == 0 }) else { return nil }
        return String(decoding: b[9..<17].prefix { $0 != 0 }, as: UTF8.self)
    }

    /// The device ID in a paired camera's advertisement: `99 03`, 4 bytes, `00`.
    public static func deviceID(manufacturerData d: Data) -> Data? {
        let b = [UInt8](d)
        guard b.count == 7, b[0] == 0x99, b[1] == 0x03 else { return nil }
        return Data(b[2..<6])
    }
}

/// Nikon "Connection to remote": a four-stage handshake on every connect,
/// then press/release. No focus control, no geotag, no decoded ack (timed
/// press, *assumed*). Bulb runs as Time: one press/release opens the
/// shutter and the next closes it.
public actor NikonRemoteDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "nikon.remote",
        brand: .nikon,
        displayName: "Nikon (Remote)",
        capabilities: [.bulbAsTime],
        ackSource: "2084 indicate (undecoded; timed press)"
    )

    public static var serviceUUIDs: [UUID] { [Nikon.service] }

    /// In its pairing menu the camera advertises the service with no
    /// manufacturer data; once paired it adds `99 03` and our device ID.
    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        guard advertisement.serviceUUIDs.contains(Nikon.service) else { return nil }
        let name = advertisement.localName ?? "Nikon"
        guard let data = advertisement.manufacturerData else {
            return CameraMatch(driverID: descriptor.id, displayName: name, modelCode: nil, isPairable: true)
        }
        guard let device = Nikon.deviceID(manufacturerData: data) else { return nil }
        return CameraMatch(driverID: descriptor.id, displayName: name, modelCode: nil, isPairable: false,
                           details: ["deviceID": device.hexString])
    }

    static let pressHold: Duration = .milliseconds(100)

    private let link: DriverLink

    public init(transport: any GATTTransport) {
        link = DriverLink(transport: transport)
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        link.events.stream()
    }

    static let script: ShotScript = {
        let press = ShotStep.write(ShotWrite(Nikon.Shutter.press, to: Nikon.remoteShutter, firesShutter: true))
        let close = ShotStep.write(ShotWrite(Nikon.Shutter.press, to: Nikon.remoteShutter))
        let release = ShotStep.write(ShotWrite(Nikon.Shutter.release, to: Nikon.remoteShutter))
        return ShotScript(focusSupported: false, focusPress: [], focusRelease: [], shootFromFocus: [],
                          shootWithoutFocus: [press, .hold(pressHold), release],
                          // Time: the same press/release opens and closes.
                          latch: [press, .hold(pressHold), release],
                          unlatch: [close, .hold(pressHold), release],
                          releaseAll: [release], minimumWriteGap: .zero, acknowledgesFocus: false,
                          unlatchToggles: true)
    }()

    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        let id = Nikon.makeID()
        progress(.registering)
        let serial = try await handshake(id: id, pairing: true)
        progress(.done)
        return CameraIdentity(values: ["id": id, "serial": Data(serial.utf8)])
    }

    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        guard let id = identity.values["id"], id.count == 8 else { throw CameraError.pairAgain }
        do {
            _ = try await handshake(id: id, pairing: false)
        } catch CameraError.pairingRejected {
            // The camera no longer takes our ID (paired with another remote).
            throw CameraError.pairAgain
        }
    }

    public func disconnect() async {
        for write in Self.script.releaseAllWrites { try? await send(write) }
        await link.disconnect()
    }

    /// Stage 1 → camera stage 2 → stage 3 → camera stage 4 with its serial.
    /// - Parameter pairing: a camera that does not answer while pairing
    ///   refused it; on reconnect it is only slow (a timeout, retried).
    private func handshake(id: Data, pairing: Bool) async throws -> String {
        let services = try await link.discover([Nikon.service])
        guard services.contains(Nikon.remotePairing) else {
            // Set to pair a smart device (SnapBridge), which xGRC cannot do.
            throw services.contains(Nikon.smartPairing)
                ? CameraError.unsupported : CameraError.missingCharacteristic(Nikon.remotePairing)
        }
        for chr in [Nikon.remoteIndication, Nikon.remoteShutter] where !services.contains(chr) {
            throw CameraError.missingCharacteristic(chr)
        }
        try await link.subscribe(Nikon.remoteIndication, decode: { .unknown(characteristic: Nikon.remoteIndication, value: $0) })
        let stages = try await link.inbox(Nikon.remotePairing)

        try await link.write(Nikon.stage1(id: id), to: Nikon.remotePairing)
        guard try await answer(stages, pairing: pairing) == Nikon.stage2 else { throw CameraError.pairingRejected }
        try await link.write(Nikon.stage3, to: Nikon.remotePairing)
        guard let serial = Nikon.serial(fromStage4: try await answer(stages, pairing: pairing)) else {
            throw CameraError.pairingRejected
        }
        return serial
    }

    private func answer(_ stages: NotificationInbox, pairing: Bool) async throws -> Data {
        do {
            return try await stages.next(timeout: Nikon.stageTimeout)
        } catch CameraError.transport(.timeout) where pairing {
            throw CameraError.pairingRejected
        }
    }

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        guard button == .shutter else { return .unsupported }
        try await send(ShotWrite(Nikon.Shutter.press, to: Nikon.remoteShutter, firesShutter: true))
        return .sent
    }

    public func release(_ button: CameraButton) async throws {
        guard button == .shutter else { return }
        try await send(ShotWrite(Nikon.Shutter.release, to: Nikon.remoteShutter))
    }

    public func send(_ write: ShotWrite) async throws {
        try await link.send(write)
    }
}
