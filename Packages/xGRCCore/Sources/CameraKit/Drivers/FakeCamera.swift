import BLEKit
import Foundation

/// A simulated Sony body behind the `GATTTransport` protocol, with the remote,
/// status, pairing and location services. The real
/// `SonyDriver` runs on top of it, so the Demo camera (shown to App Review and
/// usable without hardware) and the unit tests exercise the same driver code
/// as the real camera. Ack latency and faults are configurable.
public actor FakeCamera: GATTTransport {
    public struct Behavior: Sendable {
        /// Delay before `02 3F 20` after a half-press; `nil` = the camera never confirms focus.
        public var focusAckDelay: Duration?
        /// Delay before `02 A0 20` after a full press; `nil` = never confirms.
        public var shutterAckDelay: Duration?
        /// Every `FF01` write fails with ATT `0x90` (Bluetooth Rmt Ctrl Off).
        public var remoteControlOff: Bool
        /// The link drops right after the full-press write is accepted.
        public var dropLinkOnFullPress: Bool
        /// `DD21` value; the default is the α7C II's (95-byte packet).
        public var locationFeatures: Data
        /// Newer firmware with the `DD30`/`DD31` lock and enable.
        public var hasLocationLock: Bool
        /// The camera's Location Info. Link is off: `DD30`/`DD31` writes fail with `0x9D`.
        public var locationLinkOff: Bool
        /// Another device holds the location lock: `DD30` writes fail with `0x9F`.
        public var locationLockedElsewhere: Bool
        /// The lock is granted but enabling fails: `DD31` writes of `01` fail with `0x9D`.
        public var locationEnableRefused: Bool = false
        /// The camera is set to BULB: a full press opens the shutter and the
        /// next full press closes it; releasing the press changes nothing.
        public var bulbMode: Bool = false

        public init(focusAckDelay: Duration? = .milliseconds(150), shutterAckDelay: Duration? = .milliseconds(80),
                    remoteControlOff: Bool = false, dropLinkOnFullPress: Bool = false,
                    locationFeatures: Data = Data([0x06, 0x10, 0x00, 0x9C, 0x02, 0x00, 0x00]),
                    hasLocationLock: Bool = true, locationLinkOff: Bool = false,
                    locationLockedElsewhere: Bool = false) {
            self.focusAckDelay = focusAckDelay
            self.shutterAckDelay = shutterAckDelay
            self.remoteControlOff = remoteControlOff
            self.dropLinkOnFullPress = dropLinkOnFullPress
            self.locationFeatures = locationFeatures
            self.hasLocationLock = hasLocationLock
            self.locationLinkOff = locationLinkOff
            self.locationLockedElsewhere = locationLockedElsewhere
        }

        public static let instant = Behavior(focusAckDelay: .zero, shutterAckDelay: .zero)
    }

    /// One write as the camera received it.
    public struct ReceivedWrite: Hashable, Sendable {
        public let characteristic: GATTCharacteristicID
        public let data: Data
    }

    public static let advertisementData = Data([0x2D, 0x01, 0x03, 0x00, 0x65, 0x00, 0x05, 0x48, 0x22, 0xF0, 0x00, 0x21, 0x00])

    public var behavior: Behavior
    public private(set) var received: [ReceivedWrite] = []
    public private(set) var isLinkUp = true
    /// Current `DD30` (lock) and `DD31` (enable) values.
    public private(set) var locationLock: UInt8 = 0
    public private(set) var locationEnable: UInt8 = 0
    /// In `bulbMode`: the shutter is open.
    public private(set) var isBulbOpen = false

    private let sleep: @Sendable (Duration) async throws -> Void
    private var subscriptions: [GATTCharacteristicID: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    private nonisolated let links = Broadcaster<LinkEvent>()

    /// - Parameter sleep: how ack delays elapse; tests pass a manual clock.
    public init(behavior: Behavior = Behavior(),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.behavior = behavior
        self.sleep = sleep
    }

    public func setBehavior(_ behavior: Behavior) {
        self.behavior = behavior
    }

    /// The `FF01` command bytes received so far, in order.
    public func commands() -> [Data] {
        received.filter { $0.characteristic == Sony.ff01 }.map(\.data)
    }

    /// The `DD11` location packets received so far, in order.
    public func locationPackets() -> [Data] {
        received.filter { $0.characteristic == Sony.dd11 }.map(\.data)
    }

    public func clearReceived() {
        received.removeAll()
    }

    // MARK: Simulation controls

    /// The camera goes out of range.
    ///
    /// - Parameter isReconnecting: whether the OS keeps a pending connect.
    ///   A link from `pair()` (no auto reconnect) drops with `false`.
    public func dropLink(isReconnecting: Bool = true) {
        guard isLinkUp else { return }
        isLinkUp = false
        for continuation in subscriptions.values {
            continuation.finish(throwing: GATTError.disconnected(.connectionTimeout))
        }
        subscriptions.removeAll()
        links.yield(.disconnected(.connectionTimeout, isReconnecting: isReconnecting))
    }

    /// The camera was switched off and on (or its battery swapped): an open
    /// bulb ended, and the location lock and enable are cleared.
    public func powerCycle() {
        isBulbOpen = false
        locationLock = 0
        locationEnable = 0
    }

    /// The camera is back; the OS re-established the link.
    public func restoreLink() {
        guard !isLinkUp else { return }
        isLinkUp = true
        links.yield(.reconnected)
    }

    /// A fresh connection from the central (no reconnect event).
    public func connectLink() {
        isLinkUp = true
    }

    /// Sends a notification as the camera would.
    public func notify(_ value: Data, on chr: GATTCharacteristicID = Sony.ff02) {
        subscriptions[chr]?.yield(value)
    }

    // MARK: GATTTransport

    public func discover(services: [UUID]) async throws -> [GATTService] {
        try requireLink()
        var location = [
            GATTCharacteristic(id: Sony.dd01, properties: [.notify]),
            GATTCharacteristic(id: Sony.dd11, properties: [.write]),
            GATTCharacteristic(id: Sony.dd21, properties: [.read]),
        ]
        if behavior.hasLocationLock {
            location += [GATTCharacteristic(id: Sony.dd30, properties: [.read, .write]),
                         GATTCharacteristic(id: Sony.dd31, properties: [.read, .write])]
        }
        let all = [
            GATTService(uuid: Sony.remoteService, characteristics: [
                GATTCharacteristic(id: Sony.ff01, properties: [.write]),
                GATTCharacteristic(id: Sony.ff02, properties: [.notify]),
            ]),
            GATTService(uuid: Sony.statusService, characteristics: [
                GATTCharacteristic(id: Sony.cc02, properties: [.write]),
                GATTCharacteristic(id: Sony.cc09, properties: [.read]),
            ]),
            GATTService(uuid: Sony.locationService, characteristics: location),
            GATTService(uuid: Sony.pairingService, characteristics: [
                GATTCharacteristic(id: Sony.ee01, properties: [.write]),
            ]),
        ]
        return services.isEmpty ? all : all.filter { services.contains($0.uuid) }
    }

    public func read(_ chr: GATTCharacteristicID) async throws -> Data {
        try requireLink()
        if subscriptions[chr] != nil { throw GATTError.readOnSubscribedCharacteristic(chr) }
        switch chr {
        case Sony.cc09: return Data([0x00, 0x03, 0x00, 0x01, 0x01])
        case Sony.dd21: return behavior.locationFeatures
        case Sony.dd30 where behavior.hasLocationLock: return Data([locationLock])
        case Sony.dd31 where behavior.hasLocationLock: return Data([locationEnable])
        default: throw GATTError.characteristicNotFound(chr)
        }
    }

    public func write(_ data: Data, to chr: GATTCharacteristicID) async throws {
        try requireLink()
        let lockChars = behavior.hasLocationLock ? [Sony.dd30, Sony.dd31] : []
        guard [Sony.ff01, Sony.ee01, Sony.cc02, Sony.dd11].contains(chr) || lockChars.contains(chr) else {
            throw GATTError.characteristicNotFound(chr)
        }
        if chr == Sony.ff01, behavior.remoteControlOff { throw GATTError.att(Sony.ATT.remoteControlOff) }
        if lockChars.contains(chr), data == Data([0x01]) {
            if behavior.locationLinkOff { throw GATTError.att(Sony.ATT.locationLinkOff) }
            if chr == Sony.dd30, behavior.locationLockedElsewhere { throw GATTError.att(Sony.ATT.lockedByAnotherDevice) }
            if chr == Sony.dd31, behavior.locationEnableRefused { throw GATTError.att(Sony.ATT.locationLinkOff) }
        }
        received.append(ReceivedWrite(characteristic: chr, data: data))
        switch chr {
        case Sony.dd30: locationLock = data.first ?? 0
        case Sony.dd31:
            locationEnable = data.first ?? 0
            notify(Data([0x03, 0x01, 0x02, locationEnable]), on: Sony.dd01)
        default: break
        }
        guard chr == Sony.ff01 else { return }

        switch data {
        case Sony.Command.halfDown:
            schedule(Sony.Status.focusAcquired, after: behavior.focusAckDelay)
        case Sony.Command.fullDown:
            if behavior.dropLinkOnFullPress {
                dropLink()
                return
            }
            if behavior.bulbMode, isBulbOpen {
                isBulbOpen = false
                schedule(Sony.Status.shutterReady, after: .zero)
                return
            }
            // A camera that never confirms the shutter never opened it.
            if behavior.bulbMode, behavior.shutterAckDelay != nil { isBulbOpen = true }
            schedule(Sony.Status.shutterActive, after: behavior.shutterAckDelay)
        case Sony.Command.fullUp:
            if !behavior.bulbMode { schedule(Sony.Status.shutterReady, after: .zero) }
        case Sony.Command.halfUp:
            schedule(Sony.Status.focusLost, after: .zero)
        default:
            break
        }
    }

    public func writeWithoutResponse(_ data: Data, to chr: GATTCharacteristicID) async throws {
        try await write(data, to: chr)
    }

    public func subscribe(_ chr: GATTCharacteristicID) async throws -> AsyncThrowingStream<Data, Error> {
        try requireLink()
        guard chr == Sony.ff02 || chr == Sony.dd01 else { throw GATTError.characteristicNotFound(chr) }
        subscriptions[chr]?.finish()
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        subscriptions[chr] = continuation
        return stream
    }

    public func properties(of chr: GATTCharacteristicID) async -> CharacteristicProperties {
        switch chr {
        case Sony.ff01, Sony.ee01, Sony.cc02, Sony.dd11: [.write]
        case Sony.ff02, Sony.dd01: [.notify]
        case Sony.cc09, Sony.dd21: [.read]
        case Sony.dd30, Sony.dd31: [.read, .write]
        default: []
        }
    }

    public func maximumWriteLength(withResponse: Bool) async -> Int {
        withResponse ? 512 : 155
    }

    public func readRSSI() async throws -> Int {
        try requireLink()
        return -55
    }

    public nonisolated func linkEvents() -> AsyncStream<LinkEvent> {
        links.stream()
    }

    public func disconnect() async {
        for continuation in subscriptions.values { continuation.finish() }
        subscriptions.removeAll()
        isLinkUp = false
        links.yield(.disconnected(.localTerminated, isReconnecting: false))
    }

    // MARK: Private

    private func requireLink() throws {
        guard isLinkUp else { throw GATTError.disconnected(.connectionTimeout) }
    }

    private func schedule(_ value: Data, after delay: Duration?) {
        guard let delay else { return }
        if delay == .zero {
            notify(value)
            return
        }
        let sleep = self.sleep
        Task {
            try? await sleep(delay)
            self.notify(value)
        }
    }
}

/// A `BluetoothCentral` that finds one demo camera and connects to a
/// `FakeCamera`. Used by the Demo camera switch in Settings.
public final class DemoCentral: BluetoothCentral {
    public static let peripheralID = UUID(uuidString: "D3E30000-0000-4000-8000-00000000A7C2")!
    public static let advertisement = Advertisement(
        peripheralID: peripheralID, localName: "Demo α7 IV", rssi: -50,
        manufacturerData: FakeCamera.advertisementData, serviceUUIDs: [], isConnectable: true)

    public let camera: FakeCamera

    public init(camera: FakeCamera = FakeCamera()) {
        self.camera = camera
    }

    public func currentState() async -> CentralState { .poweredOn }

    public func stateUpdates() -> AsyncStream<CentralState> {
        AsyncStream { $0.yield(.poweredOn) }
    }

    public func scan() -> AsyncStream<Advertisement> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield(Self.advertisement)
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func connect(_ peripheralID: UUID, autoReconnect: Bool, timeout: Duration?) async throws -> any GATTTransport {
        guard peripheralID == Self.peripheralID else { throw GATTError.disconnected(.connectionFailed) }
        await camera.connectLink()
        return camera
    }

    public func connectedPeripherals(withServices services: [UUID]) async -> [UUID] { [] }

    public func cancelConnection(_ peripheralID: UUID) async {
        await camera.disconnect()
    }
}
