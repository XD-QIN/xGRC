import BLEKit
import Foundation

/// GATT layout and messages of GoPro HERO9 and later (protocol reference
/// § Bluetooth protocol reference › GoPro), from GoPro's published Open
/// GoPro BLE specification and its MIT-licensed Python SDK (`open_gopro`
/// 0.22.0: `models/constants/uuids.py`, `constants.py`, `api/builders.py`,
/// `parsers/response.py`). Written from those facts; no SDK code is copied.
public enum GoPro {
    private static func chr(_ service: UUID, _ short: String) -> GATTCharacteristicID {
        GATTCharacteristicID(service: service, characteristic: uuid(short))
    }

    /// GoPro's 128-bit base, `b5f9xxxx-aa8d-11e3-9046-0002a5d5c51b`.
    static func uuid(_ short: String) -> UUID {
        UUID(uuidString: "B5F9\(short)-AA8D-11E3-9046-0002A5D5C51B")!
    }

    /// The Control and Query service, the 16-bit `FEA6` GoPro advertises.
    public static let controlService = UUID.bluetooth(0xFEA6)
    /// Commands (`GP-0072`) and their responses (`GP-0073`, notify).
    public static let command = chr(controlService, "0072")
    public static let commandResponse = chr(controlService, "0073")
    /// Settings (`GP-0074`) and their responses (`GP-0075`, notify).
    public static let settings = chr(controlService, "0074")
    public static let settingsResponse = chr(controlService, "0075")

    public enum CommandID {
        public static let setShutter: UInt8 = 0x01
        public static let loadPresetGroup: UInt8 = 0x3E
        public static let setThirdPartyClientInfo: UInt8 = 0x50
    }

    /// Preset groups for Load Preset Group (`EnumPresetGroup`).
    public enum PresetGroup {
        public static let video: UInt16 = 1000
        public static let photo: UInt16 = 1001
        public static let timelapse: UInt16 = 1002
    }

    /// Setting 91 (LED) set to 66 is the spec's BLE keep-alive.
    public static let keepAliveSetting: UInt8 = 91
    public static let keepAliveValue: UInt8 = 66
    /// The SDK sends the keep-alive every 3 s.
    public static let keepAliveInterval: Duration = .seconds(3)

    /// Response status byte: 0 success, 1 error, 2 invalid parameter.
    public static let statusSuccess: UInt8 = 0x00

    /// One packet with the 1-byte *general* header (bit 7 clear, bits 6–5
    /// `00`, bits 4–0 the payload length), for payloads up to 31 bytes.
    /// Every message xGRC sends fits.
    public static func packet(_ payload: [UInt8]) -> Data {
        precondition(payload.count < 32, "GoPro general header holds 5 bits of length")
        return Data([UInt8(payload.count)] + payload)
    }

    /// A command: ID, then (when there are parameters) their length and bytes.
    public static func command(_ id: UInt8, _ parameter: [UInt8] = []) -> Data {
        packet(parameter.isEmpty ? [id] : [id, UInt8(parameter.count)] + parameter)
    }

    public static let shutterOn = command(CommandID.setShutter, [0x01])
    public static let shutterOff = command(CommandID.setShutter, [0x00])
    public static let thirdPartyClientInfo = command(CommandID.setThirdPartyClientInfo)

    public static func loadPresetGroup(_ group: UInt16) -> Data {
        command(CommandID.loadPresetGroup, [UInt8(group >> 8), UInt8(group & 0xFF)])
    }

    public static let keepAlive = packet([keepAliveSetting, 0x01, keepAliveValue])

    /// Reassembles notification packets into messages: a packet with bit 7
    /// set continues the current message; otherwise bits 6–5 pick the
    /// general (5-bit), extended 13-bit or extended 16-bit length header.
    public struct Accumulator: Sendable {
        private var buffer: [UInt8] = []
        private var remaining = 0

        public init() {}

        /// Returns the whole message once its last packet has arrived.
        public mutating func add(_ packet: Data) -> [UInt8]? {
            var bytes = [UInt8](packet)
            guard let first = bytes.first else { return nil }
            if first & 0x80 != 0 {
                guard remaining > 0 else { return nil }
                bytes.removeFirst()
            } else {
                buffer = []
                switch (first >> 5) & 0x03 {
                case 0:
                    remaining = Int(first & 0x1F)
                    bytes.removeFirst()
                case 1:
                    guard bytes.count >= 2 else { return nil }
                    remaining = Int(first & 0x1F) << 8 | Int(bytes[1])
                    bytes.removeFirst(2)
                case 2:
                    guard bytes.count >= 3 else { return nil }
                    remaining = Int(bytes[1]) << 8 | Int(bytes[2])
                    bytes.removeFirst(3)
                default:
                    remaining = 0
                    return nil
                }
            }
            let taken = bytes.prefix(remaining)
            buffer += taken
            remaining -= taken.count
            guard remaining == 0 else { return nil }
            defer { buffer = [] }
            return buffer
        }
    }
}

/// GoPro HERO9 and later through the Open GoPro BLE API. Remote only: GoPro
/// has no command that takes the phone's location. A shot is Set Shutter
/// on; the camera's command response (`01`, status `00`) confirms it, so
/// shots count as confirmed. On every remote connect the Photo preset group
/// is loaded so the press takes a photo instead of starting a video. The
/// spec's keep-alive is sent every 3 s while connected. Untested on a
/// camera (protocol reference § GoPro).
public actor GoProDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "gopro",
        brand: .gopro,
        displayName: "GoPro",
        capabilities: [.ackShutter, .backgroundShooting],
        ackSource: "command response 01 (Set Shutter accepted)"
    )

    public static var serviceUUIDs: [UUID] { [GoPro.controlService] }

    /// GoPro cameras advertise the `FEA6` service.
    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        guard advertisement.serviceUUIDs.contains(GoPro.controlService) else { return nil }
        return CameraMatch(driverID: descriptor.id, displayName: advertisement.localName ?? "GoPro",
                           modelCode: nil, isPairable: true)
    }

    private let link: DriverLink
    private let keepAliveEvery: Duration?
    private var keepAliveTask: Task<Void, Never>?
    private var usesRemote = true
    private var responses = GoPro.Accumulator()

    public init(transport: any GATTTransport) {
        self.init(transport: transport, keepAliveEvery: GoPro.keepAliveInterval)
    }

    /// - Parameter keepAliveEvery: `nil` turns the keep-alive off (tests).
    init(transport: any GATTTransport, keepAliveEvery: Duration?) {
        link = DriverLink(transport: transport, adaptiveWrites: true)
        self.keepAliveEvery = keepAliveEvery
    }

    public func setFeatures(remote: Bool, geotag: Bool) {
        usesRemote = remote
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        link.events.stream()
    }

    static let script: ShotScript = {
        let press = ShotStep.write(ShotWrite(GoPro.shutterOn, to: GoPro.command, firesShutter: true))
        let shot: [ShotStep] = [press, .awaitAck(.shutter, timeout: .seconds(3), optional: false)]
        // No half-press and no bulb. A photo needs no "shutter off", and
        // releaseAll stays empty so a disconnect never stops a video the
        // user started on the camera.
        return ShotScript(focusSupported: false, focusPress: [], focusRelease: [], shootFromFocus: [],
                          shootWithoutFocus: shot, latch: [], unlatch: [], releaseAll: [],
                          minimumWriteGap: .zero, acknowledgesFocus: false)
    }()

    // MARK: Pairing and reconnect

    /// The camera must be in its pairing screen the first time. Its
    /// characteristics need an encrypted link, so subscribing to the command
    /// response raises the system pairing dialog.
    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        progress(.bonding)
        try await connect(window: DriverLink.bondingWindow)
        progress(.done)
        return .bondOnly
    }

    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        try await connect(window: DriverLink.writeTimeout)
    }

    public func disconnect() async {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        await link.disconnect()
    }

    private func connect(window: Duration) async throws {
        keepAliveTask?.cancel()
        responses = GoPro.Accumulator()
        try await link.discover([GoPro.controlService],
                                required: [GoPro.command, GoPro.commandResponse, GoPro.settings])
        try await link.subscribe(GoPro.commandResponse, timeout: window, handler: { [weak self] value in
            await self?.received(value)
        })
        // Tells the camera a third-party client is connected (the SDK's first command).
        try await link.write(GoPro.thirdPartyClientInfo, to: GoPro.command, timeout: window)
        if usesRemote {
            try await link.write(GoPro.loadPresetGroup(GoPro.PresetGroup.photo), to: GoPro.command)
        }
        startKeepAlive()
    }

    private func startKeepAlive() {
        guard let interval = keepAliveEvery else { return }
        keepAliveTask = Task { [weak self, link] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, self != nil else { return }
                try? await link.send(ShotWrite(GoPro.keepAlive, to: GoPro.settings))
            }
        }
    }

    /// A Set Shutter response with status success is the shot confirmation;
    /// everything else is logged for the support table.
    private func received(_ packet: Data) {
        guard let message = responses.add(packet) else { return }
        if message.count >= 2, message[0] == GoPro.CommandID.setShutter, message[1] == GoPro.statusSuccess {
            link.events.yield(.shutterActive)
        } else {
            link.events.yield(.unknown(characteristic: GoPro.commandResponse, value: Data(message)))
        }
    }

    // MARK: Buttons

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        guard button == .shutter else { return .unsupported }
        try await send(ShotWrite(GoPro.shutterOn, to: GoPro.command, firesShutter: true))
        return .sent
    }

    public func release(_ button: CameraButton) async throws {}

    public func send(_ write: ShotWrite) async throws {
        try await link.send(write)
    }
}
