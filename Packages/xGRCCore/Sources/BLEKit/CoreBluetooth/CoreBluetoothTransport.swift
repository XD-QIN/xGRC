#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
import Foundation

/// `GATTTransport` over one `CBPeripheral`. All state is confined to the
/// central's serial queue, which is also where every delegate callback runs.
///
/// Core Bluetooth callbacks carry no request ID, so reads, writes and
/// notification-state changes are matched per characteristic in FIFO order.
/// A read on a subscribed characteristic is refused because its value would
/// arrive on the same callback as a notification.
final class CoreBluetoothTransport: NSObject, GATTTransport, @unchecked Sendable {
    let peripheral: CBPeripheral
    private weak var central: CoreBluetoothCentral?
    private let queue: DispatchQueue
    private let links = Broadcaster<LinkEvent>()

    // Queue-confined state.
    private var characteristics: [GATTCharacteristicID: CBCharacteristic] = [:]
    private var discovery: Pending<[GATTService]>?
    private var servicesAwaitingCharacteristics = 0
    private var reads: [GATTCharacteristicID: [Pending<Data>]] = [:]
    private var writes: [GATTCharacteristicID: [Pending<Void>]] = [:]
    private var notifyChanges: [GATTCharacteristicID: [Pending<Void>]] = [:]
    private var subscriptions: [GATTCharacteristicID: (token: UUID, continuation: AsyncThrowingStream<Data, Error>.Continuation)] = [:]
    private var readyWaiters: [Pending<Void>] = []
    private var rssiWaiters: [Pending<Int>] = []
    /// Connected as far as this transport has heard: set on connect, cleared
    /// on disconnect. The central reads it when Bluetooth goes off.
    private(set) var isConnected = false

    init(peripheral: CBPeripheral, central: CoreBluetoothCentral) {
        self.peripheral = peripheral
        self.central = central
        self.queue = central.queue
        super.init()
        peripheral.delegate = self
    }

    // MARK: GATTTransport

    func discover(services: [UUID]) async throws -> [GATTService] {
        try await perform { (pending: Pending<[GATTService]>) in
            try self.requireConnected()
            self.discovery?.fail(CancellationError())
            self.discovery = pending
            self.peripheral.discoverServices(services.isEmpty ? nil : services.map(CBUUID.init(foundation:)))
        }
    }

    func read(_ chr: GATTCharacteristicID) async throws -> Data {
        try await perform { (pending: Pending<Data>) in
            try self.requireConnected()
            guard self.subscriptions[chr] == nil else { throw GATTError.readOnSubscribedCharacteristic(chr) }
            let characteristic = try self.characteristic(chr)
            self.reads[chr, default: []].append(pending)
            self.peripheral.readValue(for: characteristic)
        }
    }

    func write(_ data: Data, to chr: GATTCharacteristicID) async throws {
        try await perform { (pending: Pending<Void>) in
            try self.requireConnected()
            let characteristic = try self.characteristic(chr)
            self.writes[chr, default: []].append(pending)
            self.peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }

    func writeWithoutResponse(_ data: Data, to chr: GATTCharacteristicID) async throws {
        try await perform { (pending: Pending<Void>) in
            try self.requireConnected()
            _ = try self.characteristic(chr)
            if self.peripheral.canSendWriteWithoutResponse {
                pending.succeed(())
            } else {
                self.readyWaiters.append(pending)
            }
        }
        try await perform { (pending: Pending<Void>) in
            try self.requireConnected()
            let characteristic = try self.characteristic(chr)
            self.peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            pending.succeed(())
        }
    }

    /// The stream is registered before the CCCD write, so a value the
    /// camera sends the moment notifications are on is not lost.
    func subscribe(_ chr: GATTCharacteristicID) async throws -> AsyncThrowingStream<Data, Error> {
        let token = UUID()
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard self.subscriptions[chr]?.token == token else { return }
                self.subscriptions[chr] = nil
                // Nobody listens any more: notifications off, so the camera
                // stops waking the app for them (the watch's wake-up budget).
                guard self.peripheral.state == .connected, let characteristic = self.characteristics[chr] else { return }
                // Its callback takes this slot in the FIFO; nothing awaits it.
                self.notifyChanges[chr, default: []].append(Pending<Void>())
                self.peripheral.setNotifyValue(false, for: characteristic)
            }
        }
        do {
            try await perform { (pending: Pending<Void>) in
                try self.requireConnected()
                let characteristic = try self.characteristic(chr)
                self.subscriptions[chr]?.continuation.finish()
                self.subscriptions[chr] = (token, continuation)
                self.notifyChanges[chr, default: []].append(pending)
                self.peripheral.setNotifyValue(true, for: characteristic)
            }
        } catch {
            // Unregisters it (onTermination) so a read is allowed again.
            continuation.finish(throwing: error)
            throw error
        }
        return stream
    }

    func properties(of chr: GATTCharacteristicID) async -> CharacteristicProperties {
        (try? await perform { (pending: Pending<CharacteristicProperties>) in
            pending.succeed(self.characteristics[chr].map { CharacteristicProperties($0.properties) } ?? [])
        }) ?? []
    }

    func maximumWriteLength(withResponse: Bool) async -> Int {
        (try? await perform { (pending: Pending<Int>) in
            pending.succeed(self.peripheral.maximumWriteValueLength(for: withResponse ? .withResponse : .withoutResponse))
        }) ?? 20
    }

    func readRSSI() async throws -> Int {
        try await perform { (pending: Pending<Int>) in
            try self.requireConnected()
            self.rssiWaiters.append(pending)
            self.peripheral.readRSSI()
        }
    }

    func linkEvents() -> AsyncStream<LinkEvent> {
        links.stream()
    }

    func disconnect() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.central?.cancel(self.peripheral)
                continuation.resume()
            }
        }
    }

    // MARK: Called by the central, on the queue

    /// A peripheral that was already connected (restored, or connected by
    /// another app) when a connect was asked for.
    func markConnected() {
        isConnected = true
    }

    func didConnect(isReconnect: Bool) {
        isConnected = true
        peripheral.delegate = self
        if isReconnect { links.yield(.reconnected) }
    }

    /// A connect attempt failed. The bond being gone always reaches the
    /// session (*Pair again*); any other failure of an auto-reconnect,
    /// which nobody awaits, becomes a disconnect so the session queues a
    /// new pending connect. A caller awaiting `connect` gets the error itself.
    func didFailToConnect(error: GATTError, hadWaiters: Bool) {
        if error == .peerRemovedPairing {
            links.yield(.bondRemoved)
            return
        }
        guard !hadWaiters else { return }
        let reason: LinkReason
        if case .disconnected(let r) = error { reason = r } else { reason = .connectionFailed }
        links.yield(.disconnected(reason, isReconnecting: false))
    }

    func didDisconnect(error: Error?, isReconnecting: Bool) {
        isConnected = false
        let mapped = error.map(GATTError.init(coreBluetooth:))
        let reason: LinkReason
        switch mapped {
        case .disconnected(let r)?: reason = r
        case .peerRemovedPairing?: reason = .peerTerminated
        case .none: reason = .localTerminated
        default: reason = .other(code: (error as NSError?)?.code ?? -1)
        }
        failAll(GATTError.disconnected(reason))
        if mapped == .peerRemovedPairing { links.yield(.bondRemoved) }
        links.yield(.disconnected(reason, isReconnecting: isReconnecting))
    }

    // MARK: Private

    private func perform<T: Sendable>(_ register: @escaping @Sendable (Pending<T>) throws -> Void) async throws -> T {
        let pending = Pending<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    pending.attach(continuation)
                    guard !pending.isFinished else { return }
                    do { try register(pending) } catch { pending.fail(error) }
                }
            }
        } onCancel: {
            // The slot stays in its FIFO until Core Bluetooth calls back.
            queue.async { pending.fail(CancellationError()) }
        }
    }

    private func requireConnected() throws {
        guard peripheral.state == .connected else { throw GATTError.disconnected(.other(code: 0)) }
    }

    private func characteristic(_ id: GATTCharacteristicID) throws -> CBCharacteristic {
        guard let characteristic = characteristics[id] else { throw GATTError.characteristicNotFound(id) }
        return characteristic
    }

    private func id(of characteristic: CBCharacteristic) -> GATTCharacteristicID? {
        guard let service = characteristic.service else { return nil }
        return GATTCharacteristicID(service: service.uuid.foundationUUID, characteristic: characteristic.uuid.foundationUUID)
    }

    private func failAll(_ error: GATTError) {
        discovery?.fail(error)
        discovery = nil
        for pending in reads.values.flatMap({ $0 }) { pending.fail(error) }
        for pending in writes.values.flatMap({ $0 }) { pending.fail(error) }
        for pending in notifyChanges.values.flatMap({ $0 }) { pending.fail(error) }
        for pending in readyWaiters { pending.fail(error) }
        for pending in rssiWaiters { pending.fail(error) }
        reads.removeAll()
        writes.removeAll()
        notifyChanges.removeAll()
        readyWaiters.removeAll()
        rssiWaiters.removeAll()
        for subscription in subscriptions.values { subscription.continuation.finish(throwing: error) }
        subscriptions.removeAll()
    }

    private func finishDiscoveryIfDone() {
        guard servicesAwaitingCharacteristics == 0, let discovery else { return }
        self.discovery = nil
        let services = (peripheral.services ?? []).map { service in
            let serviceUUID = service.uuid.foundationUUID
            return GATTService(uuid: serviceUUID, characteristics: (service.characteristics ?? []).map {
                GATTCharacteristic(id: GATTCharacteristicID(service: serviceUUID, characteristic: $0.uuid.foundationUUID),
                                   properties: CharacteristicProperties($0.properties))
            })
        }
        discovery.succeed(services)
    }
}

// MARK: CBPeripheralDelegate

extension CoreBluetoothTransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            discovery?.fail(GATTError(coreBluetooth: error))
            discovery = nil
            return
        }
        let services = peripheral.services ?? []
        servicesAwaitingCharacteristics = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        finishDiscoveryIfDone()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if let id = id(of: characteristic) { characteristics[id] = characteristic }
        }
        servicesAwaitingCharacteristics = max(0, servicesAwaitingCharacteristics - 1)
        finishDiscoveryIfDone()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let id = id(of: characteristic) else { return }
        if var pendingReads = reads[id], !pendingReads.isEmpty {
            let pending = pendingReads.removeFirst()
            reads[id] = pendingReads
            if let error {
                pending.fail(GATTError(coreBluetooth: error))
            } else {
                pending.succeed(characteristic.value ?? Data())
            }
            return
        }
        if let error {
            #if os(watchOS)
            let code = (error as NSError).code
            if (error as NSError).domain == CBErrorDomain {
                if code == CBError.Code.leGattNearBackgroundNotificationLimit.rawValue {
                    links.yield(.backgroundBudget(exceeded: false))
                } else if code == CBError.Code.leGattExceededBackgroundNotificationLimit.rawValue {
                    links.yield(.backgroundBudget(exceeded: true))
                }
            }
            #endif
            return
        }
        subscriptions[id]?.continuation.yield(characteristic.value ?? Data())
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let id = id(of: characteristic), var pendingWrites = writes[id], !pendingWrites.isEmpty else { return }
        let pending = pendingWrites.removeFirst()
        writes[id] = pendingWrites
        if let error { pending.fail(GATTError(coreBluetooth: error)) } else { pending.succeed(()) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let id = id(of: characteristic), var pendingChanges = notifyChanges[id], !pendingChanges.isEmpty else { return }
        let pending = pendingChanges.removeFirst()
        notifyChanges[id] = pendingChanges
        if let error { pending.fail(GATTError(coreBluetooth: error)) } else { pending.succeed(()) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters { waiter.succeed(()) }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard !rssiWaiters.isEmpty else { return }
        let pending = rssiWaiters.removeFirst()
        if let error { pending.fail(GATTError(coreBluetooth: error)) } else { pending.succeed(RSSI.intValue) }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        let invalid = Set(invalidatedServices.map { $0.uuid.foundationUUID })
        characteristics = characteristics.filter { !invalid.contains($0.key.service) }
        links.yield(.servicesModified)
    }
}

extension CharacteristicProperties {
    init(_ properties: CBCharacteristicProperties) {
        var result: CharacteristicProperties = []
        if properties.contains(.read) { result.insert(.read) }
        if properties.contains(.write) { result.insert(.write) }
        if properties.contains(.writeWithoutResponse) { result.insert(.writeWithoutResponse) }
        if properties.contains(.notify) { result.insert(.notify) }
        if properties.contains(.indicate) { result.insert(.indicate) }
        self = result
    }
}
#endif
