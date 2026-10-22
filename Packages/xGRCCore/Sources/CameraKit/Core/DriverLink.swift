import BLEKit
import Foundation

/// Transport plumbing the Fujifilm, Canon, Nikon and Ricoh drivers share:
/// discovery with a required-characteristic check, writes kept in call order
/// with a timeout, notification pumps into the driver's event stream, and
/// inboxes for handshakes that wait for the camera's answer. Every error
/// leaves as a `CameraError`.
public actor DriverLink {
    public static let writeTimeout: Duration = .seconds(5)
    /// The system pairing dialog can stay up while the user confirms on the camera.
    public static let bondingWindow: Duration = .seconds(60)

    public let transport: any GATTTransport
    /// The driver's decoded camera events.
    public nonisolated let events = Broadcaster<CameraEvent>()
    public private(set) var services: [GATTService] = []

    private let mapError: @Sendable (GATTError) -> CameraError
    private let adaptiveWrites: Bool
    private var writeTail: Task<Void, Never>?
    private var pumps: [GATTCharacteristicID: Task<Void, Never>] = [:]

    /// - Parameter adaptiveWrites: write with response wherever the camera's
    ///   characteristic allows it, else without, whatever the `ShotWrite`
    ///   says. For brands whose sources disagree on the write type (Canon).
    public init(transport: any GATTTransport, adaptiveWrites: Bool = false,
                mapError: @escaping @Sendable (GATTError) -> CameraError = DriverLink.standardError) {
        self.transport = transport
        self.adaptiveWrites = adaptiveWrites
        self.mapError = mapError
    }

    /// The bond is gone: pair again. Everything else is a transport error.
    public static func standardError(_ error: GATTError) -> CameraError {
        switch error {
        case .peerRemovedPairing: .pairAgain
        default: .transport(error)
        }
    }

    // MARK: Discovery

    /// Discovers `uuids` and throws `missingCharacteristic` for the first of
    /// `required` the camera does not have.
    @discardableResult
    public func discover(_ uuids: [UUID], required: [GATTCharacteristicID] = []) async throws -> [GATTService] {
        let transport = self.transport
        let found = try await mapped(.seconds(10)) { try await transport.discover(services: uuids) }
        for chr in required where !found.contains(chr) {
            throw CameraError.missingCharacteristic(chr)
        }
        services = found
        return found
    }

    public func has(_ chr: GATTCharacteristicID) -> Bool {
        services.contains(chr)
    }

    // MARK: Reads and writes

    public func read(_ chr: GATTCharacteristicID, timeout: Duration = DriverLink.writeTimeout) async throws -> Data {
        let transport = self.transport
        return try await mapped(timeout) { try await transport.read(chr) }
    }

    public func write(_ data: Data, to chr: GATTCharacteristicID, withResponse: Bool = true,
                      timeout: Duration = DriverLink.writeTimeout) async throws {
        try await send(ShotWrite(data, to: chr, withResponse: withResponse), timeout: timeout)
    }

    /// Writes are chained so a release from a cancel never overtakes a shot in flight.
    public func send(_ write: ShotWrite, timeout: Duration = DriverLink.writeTimeout) async throws {
        try await send([write], timeout: timeout)
    }

    /// Sends `writes` back to back in one slot of the chain, so a two-write
    /// command (Fujifilm) is never split by another write.
    public func send(_ writes: [ShotWrite], timeout: Duration = DriverLink.writeTimeout) async throws {
        let previous = writeTail
        let transport = self.transport
        let mapError = self.mapError
        let planned = writes.map { write -> (Data, GATTCharacteristicID, Bool) in
            var withResponse = write.withResponse
            if adaptiveWrites, let properties = services.characteristic(write.characteristic)?.properties {
                withResponse = properties.contains(.write)
            }
            return (write.data, write.characteristic, withResponse)
        }
        let operation = Task { () -> Result<Void, Error> in
            await previous?.value
            do {
                for (data, chr, withResponse) in planned {
                    try await Self.mapped(timeout, mapError) {
                        if withResponse {
                            try await transport.write(data, to: chr)
                        } else {
                            try await transport.writeWithoutResponse(data, to: chr)
                        }
                    }
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        writeTail = Task { _ = await operation.value }
        try await operation.value.get()
    }

    // MARK: Notifications

    /// Subscribes and hands every value to `handler` until the link drops.
    public func subscribe(_ chr: GATTCharacteristicID, timeout: Duration = DriverLink.writeTimeout,
                          handler: @escaping @Sendable (Data) async -> Void) async throws {
        let transport = self.transport
        let stream = try await mapped(timeout) { try await transport.subscribe(chr) }
        pumps[chr]?.cancel()
        pumps[chr] = Task {
            do {
                for try await value in stream { await handler(value) }
            } catch {
                // Link lost; the session reconnects and the driver subscribes again.
            }
        }
    }

    /// Subscribes and publishes each decoded value as a camera event.
    public func subscribe(_ chr: GATTCharacteristicID, timeout: Duration = DriverLink.writeTimeout,
                          decode: @escaping @Sendable (Data) -> CameraEvent) async throws {
        let events = self.events
        try await subscribe(chr, timeout: timeout) { value in events.yield(decode(value)) }
    }

    /// Subscribes into an inbox a handshake can await value by value.
    public func inbox(_ chr: GATTCharacteristicID, timeout: Duration = DriverLink.writeTimeout) async throws -> NotificationInbox {
        let inbox = NotificationInbox()
        let transport = self.transport
        let stream = try await mapped(timeout) { try await transport.subscribe(chr) }
        pumps[chr]?.cancel()
        pumps[chr] = Task {
            do {
                for try await value in stream { await inbox.deliver(value) }
                await inbox.end(GATTError.disconnected(.localTerminated))
            } catch {
                await inbox.end(error)
            }
        }
        return inbox
    }

    public func stopPumps() {
        for pump in pumps.values { pump.cancel() }
        pumps.removeAll()
    }

    public func disconnect() async {
        stopPumps()
        await transport.disconnect()
    }

    // MARK: Errors

    private func mapped<T: Sendable>(_ timeout: Duration, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await Self.mapped(timeout, mapError, body)
    }

    private static func mapped<T: Sendable>(_ timeout: Duration, _ mapError: @Sendable (GATTError) -> CameraError,
                                            _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        do {
            return try await withTimeout(timeout, body)
        } catch let error as GATTError {
            throw mapError(error)
        }
    }
}

/// Buffers one characteristic's notifications so a handshake can await them
/// in order (Nikon's stage messages, Canon's pairing answer).
public actor NotificationInbox {
    private var buffer: [Data] = []
    private var waiter: CheckedContinuation<Data, Error>?
    private var ended: Error?

    public init() {}

    public func deliver(_ value: Data) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: value)
        } else {
            buffer.append(value)
        }
    }

    public func end(_ error: Error) {
        ended = error
        waiter?.resume(throwing: error)
        waiter = nil
    }

    /// The next value, or `GATTError.timeout` (mapped to a `CameraError`).
    public func next(timeout: Duration) async throws -> Data {
        do {
            return try await withTimeout(timeout) { try await self.next() }
        } catch let error as GATTError {
            throw DriverLink.standardError(error)
        }
    }

    private func next() async throws -> Data {
        if !buffer.isEmpty { return buffer.removeFirst() }
        if let ended { throw ended }
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
            }
        } onCancel: {
            Task { await self.cancelWaiter() }
        }
    }

    private func cancelWaiter() {
        waiter?.resume(throwing: CancellationError())
        waiter = nil
    }
}
