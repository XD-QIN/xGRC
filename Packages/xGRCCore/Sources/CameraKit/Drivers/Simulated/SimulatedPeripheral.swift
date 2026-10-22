import BLEKit
import Foundation

/// A GATT server behind the `GATTTransport` protocol, configured per brand by
/// the factories in `SimulatedBodies.swift`. The real drivers run on top of
/// it, so their tests exercise the same code as a real camera. `FakeCamera`
/// stays the richer Sony body the Demo camera uses.
public actor SimulatedPeripheral: GATTTransport {
    /// One write as the camera received it.
    public struct Write: Hashable, Sendable {
        public let characteristic: GATTCharacteristicID
        public let data: Data
        public let withResponse: Bool
    }

    /// Reacts to a write the way the camera would: notify, change a value, fail later writes.
    public typealias Responder = @Sendable (Write, SimulatedPeripheral) async -> Void

    public private(set) var writes: [Write] = []
    public private(set) var isLinkUp = true

    private let layout: [GATTService]
    private var values: [GATTCharacteristicID: Data]
    private var failures: [GATTCharacteristicID: GATTError] = [:]
    private var nextFailures: [GATTCharacteristicID: [GATTError]] = [:]
    private var responder: Responder?
    private var subscriptions: [GATTCharacteristicID: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    private nonisolated let links = Broadcaster<LinkEvent>()

    public init(services: [GATTService], values: [GATTCharacteristicID: Data] = [:], responder: Responder? = nil) {
        self.layout = services
        self.values = values
        self.responder = responder
    }

    // MARK: Simulation controls

    public func setResponder(_ responder: Responder?) {
        self.responder = responder
    }

    public func setValue(_ value: Data, for chr: GATTCharacteristicID) {
        values[chr] = value
    }

    public func value(of chr: GATTCharacteristicID) -> Data? {
        values[chr]
    }

    /// Every later read, write or subscription on `chr` fails with `error` (`nil` clears it).
    public func fail(_ chr: GATTCharacteristicID, with error: GATTError?) {
        failures[chr] = error
    }

    /// Only the next write on `chr` fails with `error`; later ones go through.
    /// `.timeout` stands for a write the camera may or may not have taken.
    public func failNextWrite(to chr: GATTCharacteristicID, with error: GATTError) {
        nextFailures[chr, default: []].append(error)
    }

    /// Sends a notification or indication as the camera would.
    public func notify(_ value: Data, on chr: GATTCharacteristicID) {
        subscriptions[chr]?.yield(value)
    }

    public func isSubscribed(_ chr: GATTCharacteristicID) -> Bool {
        subscriptions[chr] != nil
    }

    /// The values written to `chr` so far, in order.
    public func writes(to chr: GATTCharacteristicID) -> [Data] {
        writes.filter { $0.characteristic == chr }.map(\.data)
    }

    public func clearWrites() {
        writes.removeAll()
    }

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

    public func restoreLink() {
        guard !isLinkUp else { return }
        isLinkUp = true
        links.yield(.reconnected)
    }

    // MARK: GATTTransport

    public func discover(services: [UUID]) async throws -> [GATTService] {
        try requireLink()
        return services.isEmpty ? layout : layout.filter { services.contains($0.uuid) }
    }

    public func read(_ chr: GATTCharacteristicID) async throws -> Data {
        try requireLink()
        guard let properties = layout.characteristic(chr)?.properties, properties.contains(.read) else {
            throw GATTError.characteristicNotFound(chr)
        }
        if subscriptions[chr] != nil { throw GATTError.readOnSubscribedCharacteristic(chr) }
        if let failure = failures[chr] { throw failure }
        return values[chr] ?? Data()
    }

    public func write(_ data: Data, to chr: GATTCharacteristicID) async throws {
        try await receive(data, to: chr, withResponse: true)
    }

    public func writeWithoutResponse(_ data: Data, to chr: GATTCharacteristicID) async throws {
        try await receive(data, to: chr, withResponse: false)
    }

    public func subscribe(_ chr: GATTCharacteristicID) async throws -> AsyncThrowingStream<Data, Error> {
        try requireLink()
        guard let properties = layout.characteristic(chr)?.properties,
              !properties.isDisjoint(with: [.notify, .indicate]) else {
            throw GATTError.characteristicNotFound(chr)
        }
        if let failure = failures[chr] { throw failure }
        subscriptions[chr]?.finish()
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        subscriptions[chr] = continuation
        return stream
    }

    public func properties(of chr: GATTCharacteristicID) async -> CharacteristicProperties {
        layout.characteristic(chr)?.properties ?? []
    }

    public func maximumWriteLength(withResponse: Bool) async -> Int {
        withResponse ? 512 : 182
    }

    public func readRSSI() async throws -> Int {
        try requireLink()
        return -60
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

    private func receive(_ data: Data, to chr: GATTCharacteristicID, withResponse: Bool) async throws {
        try requireLink()
        guard let properties = layout.characteristic(chr)?.properties,
              !properties.isDisjoint(with: [.write, .writeWithoutResponse]) else {
            throw GATTError.characteristicNotFound(chr)
        }
        if let failure = failures[chr] { throw failure }
        if var pending = nextFailures[chr], !pending.isEmpty {
            let failure = pending.removeFirst()
            nextFailures[chr] = pending
            throw failure
        }
        let write = Write(characteristic: chr, data: data, withResponse: withResponse)
        writes.append(write)
        if properties.contains(.read) { values[chr] = data }
        await responder?(write, self)
    }

    private func requireLink() throws {
        guard isLinkUp else { throw GATTError.disconnected(.connectionTimeout) }
    }
}

extension GATTService {
    /// Shorthand for the simulated bodies' layouts.
    public static func simulated(_ uuid: UUID, _ characteristics: [GATTCharacteristicID: CharacteristicProperties]) -> GATTService {
        GATTService(uuid: uuid, characteristics: characteristics
            .sorted { $0.key.characteristic.uuidString < $1.key.characteristic.uuidString }
            .map { GATTCharacteristic(id: $0.key, properties: $0.value) })
    }
}
