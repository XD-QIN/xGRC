import Foundation

/// What a camera driver needs from the radio. Implemented by
/// `CoreBluetoothTransport` (real), `RecordingTransport` (logging decorator)
/// and by test fakes such as CameraKit's `FakeCamera`.
///
/// Cancellation rule: an awaited operation that is cancelled returns
/// `CancellationError` at once but keeps its queue slot until Core Bluetooth
/// calls back or the link drops, because Core Bluetooth cannot cancel an
/// in-flight ATT request and its callbacks carry no request ID. Timeouts are
/// applied by callers with `withTimeout(_:_:)`, which relies on this.
public protocol GATTTransport: Sendable {
    /// Discovers the given services (all services when empty) and their characteristics.
    func discover(services: [UUID]) async throws -> [GATTService]
    /// Forbidden on a characteristic the driver has subscribed to.
    func read(_ chr: GATTCharacteristicID) async throws -> Data
    /// Write with response.
    func write(_ data: Data, to chr: GATTCharacteristicID) async throws
    /// Write without response; awaits peripheral readiness first.
    func writeWithoutResponse(_ data: Data, to chr: GATTCharacteristicID) async throws
    /// Resolves after the CCCD write is confirmed. The stream ends with an
    /// error when the link is lost; a new subscription is needed after reconnect.
    func subscribe(_ chr: GATTCharacteristicID) async throws -> AsyncThrowingStream<Data, Error>
    func properties(of chr: GATTCharacteristicID) async -> CharacteristicProperties
    /// Core Bluetooth has no MTU request API; this is the single-packet limit.
    func maximumWriteLength(withResponse: Bool) async -> Int
    func readRSSI() async throws -> Int
    /// A fresh stream of link events for each caller.
    func linkEvents() -> AsyncStream<LinkEvent>
    func disconnect() async
}

/// The central role: scanning and connecting. Implemented by
/// `CoreBluetoothCentral` and by `DemoCentral` in CameraKit.
public protocol BluetoothCentral: Sendable {
    func currentState() async -> CentralState
    func stateUpdates() -> AsyncStream<CentralState>
    /// Foreground scan, every advertisement, duplicates allowed. Ends when the
    /// consuming task is cancelled or the stream is dropped.
    func scan() -> AsyncStream<Advertisement>
    /// Connects to a peripheral seen in a scan or remembered from earlier.
    ///
    /// - `autoReconnect`: a pending connect with
    ///   `CBConnectPeripheralOptionEnableAutoReconnect`; it waits as long as
    ///   it takes and the OS re-establishes the link after drops.
    /// - `timeout`: only for the first connect while pairing (30 s).
    func connect(_ peripheralID: UUID, autoReconnect: Bool, timeout: Duration?) async throws -> any GATTTransport
    /// Peripherals already connected to this device (e.g. by the maker's app).
    func connectedPeripherals(withServices services: [UUID]) async -> [UUID]
    /// Cancels a pending or live connection.
    func cancelConnection(_ peripheralID: UUID) async
    /// Peripherals Core Bluetooth state restoration handed back at launch,
    /// connected or with a pending connect. Empty for other centrals.
    func restoredPeripherals() async -> [UUID]
}

extension BluetoothCentral {
    public func restoredPeripherals() async -> [UUID] { [] }
}

/// Runs `operation`, cancelling it and throwing `GATTError.timeout` if it does
/// not finish within `duration` on the continuous clock.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw GATTError.timeout
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw GATTError.timeout }
        return result
    }
}
