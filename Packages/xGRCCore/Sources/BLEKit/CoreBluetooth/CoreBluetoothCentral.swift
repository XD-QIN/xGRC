#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
import Foundation

/// The real `BluetoothCentral`. Executor rule (architecture doc § Architecture): one
/// serial queue is the `CBCentralManager` queue, every delegate callback runs
/// on it, and every piece of mutable state below is touched only on it.
/// `CBPeripheral` and `CBCharacteristic` never leave BLEKit; callers get
/// value snapshots and a `GATTTransport`.
///
/// Create exactly one, synchronously, in the app delegate's launch method, so
/// state restoration finds it under the same restore identifier.
public final class CoreBluetoothCentral: NSObject, BluetoothCentral, @unchecked Sendable {
    public static let restoreIdentifier = "xGRC.central"

    let queue = DispatchQueue(label: "xGRC.BLEKit", qos: .userInitiated)
    private var manager: CBCentralManager!
    private let states = Broadcaster<CentralState>(replayLast: true)

    // Queue-confined state.
    private var state: CentralState = .unknown
    private var scanners: [UUID: AsyncStream<Advertisement>.Continuation] = [:]
    private var isScanning = false
    /// Peripherals we have seen or restored. Core Bluetooth does not retain them.
    private var known: [UUID: CBPeripheral] = [:]
    private var transports: [UUID: CoreBluetoothTransport] = [:]
    private var connectWaiters: [UUID: [Pending<Void>]] = [:]
    /// Peripherals handed back by state restoration at launch.
    private var restored: [UUID] = []

    /// How long a connect waits for the manager's first state at launch.
    static let stateSettleTimeout: Duration = .seconds(10)

    public init(restoreIdentifier: String? = CoreBluetoothCentral.restoreIdentifier) {
        super.init()
        var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: true]
        if let restoreIdentifier {
            options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier
        }
        queue.sync {
            manager = CBCentralManager(delegate: self, queue: queue, options: options)
        }
    }

    // MARK: BluetoothCentral

    public func currentState() async -> CentralState {
        await onQueue { self.state }
    }

    public func stateUpdates() -> AsyncStream<CentralState> {
        states.stream()
    }

    public func scan() -> AsyncStream<Advertisement> {
        AsyncStream { continuation in
            let id = UUID()
            queue.async {
                self.scanners[id] = continuation
                self.updateScanning()
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    self.scanners[id] = nil
                    self.updateScanning()
                }
            }
        }
    }

    public func connect(_ peripheralID: UUID, autoReconnect: Bool, timeout: Duration?) async throws -> any GATTTransport {
        // At launch the manager reports `.unknown` until its first state
        // update; a session restored at launch must not fail on that.
        _ = await settledState()
        let transport: CoreBluetoothTransport = try await perform { pending in
            guard self.state == .poweredOn else { throw GATTError.bluetoothUnavailable(self.state) }
            guard let peripheral = self.peripheral(for: peripheralID) else {
                throw GATTError.disconnected(.connectionFailed)
            }
            let transport = self.transport(for: peripheral)
            if peripheral.state == .connected {
                transport.markConnected()
                pending.succeed(())
                return
            }
            self.connectWaiters[peripheralID, default: []].append(pending)
            var options: [String: Any] = [:]
            if autoReconnect { options[CBConnectPeripheralOptionEnableAutoReconnect] = true }
            self.manager.connect(peripheral, options: options)
            if let timeout {
                let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
                self.queue.asyncAfter(deadline: .now() + seconds) { [weak pending] in
                    guard let pending, !pending.isFinished else { return }
                    self.connectWaiters[peripheralID]?.removeAll { $0 === pending }
                    if let peripheral = self.known[peripheralID] {
                        self.manager.cancelPeripheralConnection(peripheral)
                    }
                    pending.fail(GATTError.timeout)
                }
            }
        } onCancel: { pending in
            self.connectWaiters[peripheralID]?.removeAll { $0 === pending }
            if let peripheral = self.known[peripheralID] {
                self.manager.cancelPeripheralConnection(peripheral)
            }
        } then: {
            self.transports[peripheralID]!
        }
        return transport
    }

    public func connectedPeripherals(withServices services: [UUID]) async -> [UUID] {
        await onQueue {
            guard self.state == .poweredOn else { return [] }
            let found = self.manager.retrieveConnectedPeripherals(withServices: services.map(CBUUID.init(foundation:)))
            for peripheral in found { self.known[peripheral.identifier] = peripheral }
            return found.map(\.identifier)
        }
    }

    public func restoredPeripherals() async -> [UUID] {
        // Restoration is delivered before the first state update.
        _ = await settledState()
        return await onQueue { self.restored }
    }

    public func cancelConnection(_ peripheralID: UUID) async {
        await onQueue {
            for waiter in self.connectWaiters.removeValue(forKey: peripheralID) ?? [] {
                waiter.fail(CancellationError())
            }
            // Cancelled whatever its state: after a drop the peripheral reads
            // `.disconnected` while the OS auto-reconnect is still pending,
            // and only this call stops it, so an ended session cannot
            // reconnect to the camera later.
            if let peripheral = self.peripheral(for: peripheralID) {
                self.manager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    /// The current state once it is no longer `.unknown` or `.resetting`,
    /// or whatever it is after `stateSettleTimeout`.
    private func settledState() async -> CentralState {
        let current = await currentState()
        guard current == .unknown || current == .resetting else { return current }
        let updates = states.stream()
        let timeout = Self.stateSettleTimeout
        let settled = await withTaskGroup(of: CentralState?.self) { group in
            group.addTask {
                for await state in updates where state != .unknown && state != .resetting { return state }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let settled { return settled }
        return await currentState()
    }

    // MARK: Queue helpers

    private func onQueue<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }

    /// Registers a pending operation on the queue; resumes when it finishes.
    /// On cancellation `onCancel` runs on the queue and the caller gets
    /// `CancellationError`. `then` maps the result on the queue.
    private func perform<T: Sendable, R: Sendable>(
        _ register: @escaping @Sendable (Pending<T>) throws -> Void,
        onCancel: @escaping @Sendable (Pending<T>) -> Void,
        then map: @escaping @Sendable () -> R
    ) async throws -> R {
        let pending = Pending<T>()
        _ = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    pending.attach(continuation)
                    guard !pending.isFinished else { return }
                    do { try register(pending) } catch { pending.fail(error) }
                }
            }
        } onCancel: {
            queue.async {
                guard !pending.isFinished else { return }
                onCancel(pending)
                pending.fail(CancellationError())
            }
        }
        return await onQueue(map)
    }

    private func peripheral(for id: UUID) -> CBPeripheral? {
        if let peripheral = known[id] { return peripheral }
        let found = manager.retrievePeripherals(withIdentifiers: [id]).first
        if let found { known[id] = found }
        return found
    }

    private func transport(for peripheral: CBPeripheral) -> CoreBluetoothTransport {
        if let existing = transports[peripheral.identifier] { return existing }
        let transport = CoreBluetoothTransport(peripheral: peripheral, central: self)
        transports[peripheral.identifier] = transport
        return transport
    }

    private func updateScanning() {
        let wanted = !scanners.isEmpty && state == .poweredOn
        if wanted, !isScanning {
            manager.scanForPeripherals(withServices: nil,
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            isScanning = true
        } else if !wanted, isScanning {
            if manager.state == .poweredOn { manager.stopScan() }
            isScanning = false
        }
    }

    func cancel(_ peripheral: CBPeripheral) {
        manager.cancelPeripheralConnection(peripheral)
    }
}

// MARK: CBCentralManagerDelegate

extension CoreBluetoothCentral: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = CentralState(central.state)
        if state != .poweredOn {
            isScanning = false
            for (id, waiters) in connectWaiters {
                for waiter in waiters { waiter.fail(GATTError.bluetoothUnavailable(state)) }
                connectWaiters[id] = nil
            }
            // Core Bluetooth reports no disconnect when the radio goes off,
            // and drops the pending connects with it: every live link is
            // reported down, so its session queues a new connect that waits
            // for Bluetooth to come back (Control Center off and on).
            for transport in transports.values where transport.isConnected {
                transport.didDisconnect(error: GATTError.disconnected(.connectionFailed), isReconnecting: false)
            }
        }
        updateScanning()
        states.yield(state)
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in peripherals {
            known[peripheral.identifier] = peripheral
            let transport = self.transport(for: peripheral)
            if peripheral.state == .connected { transport.markConnected() }
        }
        restored = peripherals.map(\.identifier)
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        known[peripheral.identifier] = peripheral
        let advertisement = Advertisement(
            peripheralID: peripheral.identifier,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
            rssi: RSSI.intValue,
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceUUIDs: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.foundationUUID),
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
        )
        for scanner in scanners.values { scanner.yield(advertisement) }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let transport = transport(for: peripheral)
        let waiters = connectWaiters.removeValue(forKey: peripheral.identifier) ?? []
        transport.didConnect(isReconnect: waiters.isEmpty)
        for waiter in waiters { waiter.succeed(()) }
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let mapped = error.map(GATTError.init(coreBluetooth:)) ?? .disconnected(.connectionFailed)
        let waiters = connectWaiters.removeValue(forKey: peripheral.identifier) ?? []
        for waiter in waiters { waiter.fail(mapped) }
        // A failed auto-reconnect has no waiter: the session hears it from
        // the transport, so a removed bond shows Pair again.
        transports[peripheral.identifier]?.didFailToConnect(error: mapped, hadWaiters: !waiters.isEmpty)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        transports[peripheral.identifier]?.didDisconnect(error: error, isReconnecting: isReconnecting)
    }
}

// MARK: Shared helpers

/// One awaited Core Bluetooth operation. Only touched on the BLEKit queue.
/// A cancelled operation keeps its slot in its FIFO (callbacks carry no
/// request ID), so the callback that eventually arrives is consumed by it.
final class Pending<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Error>?
    private var earlyResult: Result<T, Error>?
    private(set) var isFinished = false

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        if let earlyResult {
            continuation.resume(with: earlyResult)
        } else {
            self.continuation = continuation
        }
    }

    func succeed(_ value: T) { finish(.success(value)) }
    func fail(_ error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<T, Error>) {
        guard !isFinished else { return }
        isFinished = true
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            earlyResult = result
        }
    }
}

extension CentralState {
    init(_ state: CBManagerState) {
        switch state {
        case .poweredOn: self = .poweredOn
        case .poweredOff: self = .poweredOff
        case .unauthorized: self = .unauthorized
        case .unsupported: self = .unsupported
        case .resetting: self = .resetting
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}

extension CBUUID {
    /// Short UUIDs (`FF01`) as `CBUUID(string:)`, so they compare equal to
    /// what discovery reports; everything else by value.
    convenience init(foundation uuid: UUID) {
        let short = uuid.bluetoothDescription
        if short.count == 4 {
            self.init(string: short)
        } else {
            self.init(nsuuid: uuid)
        }
    }

    var foundationUUID: UUID {
        let bytes = [UInt8](data)
        switch bytes.count {
        case 2: return .bluetooth(UInt32(bytes[0]) << 8 | UInt32(bytes[1]))
        case 4: return .bluetooth(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default: return UUID(uuidString: uuidString) ?? UUID()
        }
    }
}

extension GATTError {
    init(coreBluetooth error: Error) {
        let ns = error as NSError
        if let gatt = error as? GATTError {
            self = gatt
        } else if ns.domain == CBATTErrorDomain {
            switch CBATTError.Code(rawValue: ns.code) {
            case .insufficientAuthentication?, .insufficientEncryption?:
                self = .insufficientAuthentication
            default:
                self = .att(UInt8(truncatingIfNeeded: ns.code))
            }
        } else if ns.domain == CBErrorDomain {
            switch CBError.Code(rawValue: ns.code) {
            case .peerRemovedPairingInformation?: self = .peerRemovedPairing
            case .connectionTimeout?: self = .disconnected(.connectionTimeout)
            case .peripheralDisconnected?: self = .disconnected(.peerTerminated)
            case .connectionFailed?: self = .disconnected(.connectionFailed)
            case .encryptionTimedOut?: self = .disconnected(.encryptionFailed)
            case .notConnected?: self = .disconnected(.other(code: ns.code))
            default: self = .other(domain: ns.domain, code: ns.code)
            }
        } else {
            self = .other(domain: ns.domain, code: ns.code)
        }
    }
}
#endif
