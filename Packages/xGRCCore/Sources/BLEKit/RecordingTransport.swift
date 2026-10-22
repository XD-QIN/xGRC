import Foundation

/// Logs every GATT operation of the wrapped transport to a `TranscriptLogger`:
/// direction, characteristic, bytes, latency and errors. Sessions wrap every
/// transport in one, so the real camera link and the demo camera produce the
/// same transcript.
public struct RecordingTransport: GATTTransport {
    public let base: any GATTTransport
    public let logger: TranscriptLogger

    public init(_ base: any GATTTransport, logger: TranscriptLogger) {
        self.base = base
        self.logger = logger
    }

    public func discover(services: [UUID]) async throws -> [GATTService] {
        let started = await logger.elapsed()
        do {
            let result = try await base.discover(services: services)
            for service in result {
                for chr in service.characteristics {
                    await logger.log(TranscriptEntry(
                        t: await logger.elapsed(), op: .discover,
                        service: service.uuid.bluetoothDescription,
                        char: chr.id.characteristic.bluetoothDescription,
                        props: chr.properties.transcriptCode))
                }
            }
            await log(.discover, nil, started: started, note: "\(result.count) services")
            return result
        } catch {
            await log(.discover, nil, started: started, error: error)
            throw error
        }
    }

    public func read(_ chr: GATTCharacteristicID) async throws -> Data {
        let started = await logger.elapsed()
        do {
            let data = try await base.read(chr)
            await log(.read, chr, started: started, bytes: data)
            return data
        } catch {
            await log(.read, chr, started: started, error: error)
            throw error
        }
    }

    public func write(_ data: Data, to chr: GATTCharacteristicID) async throws {
        let started = await logger.elapsed()
        do {
            try await base.write(data, to: chr)
            await log(.write, chr, started: started, bytes: data)
        } catch {
            await log(.write, chr, started: started, bytes: data, error: error)
            throw error
        }
    }

    public func writeWithoutResponse(_ data: Data, to chr: GATTCharacteristicID) async throws {
        let started = await logger.elapsed()
        do {
            try await base.writeWithoutResponse(data, to: chr)
            await log(.writeNoResponse, chr, started: started, bytes: data)
        } catch {
            await log(.writeNoResponse, chr, started: started, bytes: data, error: error)
            throw error
        }
    }

    public func subscribe(_ chr: GATTCharacteristicID) async throws -> AsyncThrowingStream<Data, Error> {
        let started = await logger.elapsed()
        let upstream: AsyncThrowingStream<Data, Error>
        do {
            upstream = try await base.subscribe(chr)
            await log(.subscribe, chr, started: started)
        } catch {
            await log(.subscribe, chr, started: started, error: error)
            throw error
        }
        let logger = self.logger
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in upstream {
                        await logger.log(TranscriptEntry(
                            t: await logger.elapsed(), op: .notify,
                            service: chr.service.bluetoothDescription,
                            char: chr.characteristic.bluetoothDescription,
                            bytes: value.hexString))
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func properties(of chr: GATTCharacteristicID) async -> CharacteristicProperties {
        await base.properties(of: chr)
    }

    public func maximumWriteLength(withResponse: Bool) async -> Int {
        let length = await base.maximumWriteLength(withResponse: withResponse)
        await logger.log(.note, note: "maximum write length \(withResponse ? "with" : "without") response: \(length) bytes")
        return length
    }

    public func readRSSI() async throws -> Int {
        try await base.readRSSI()
    }

    public func linkEvents() -> AsyncStream<LinkEvent> {
        let upstream = base.linkEvents()
        let logger = self.logger
        return AsyncStream { continuation in
            let task = Task {
                for await event in upstream {
                    await logger.log(TranscriptEntry(t: await logger.elapsed(), op: .link,
                                                     linkEvent: String(describing: event)))
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func disconnect() async {
        await logger.log(.link, note: "disconnect requested")
        await base.disconnect()
    }

    private func log(_ op: TranscriptEntry.Op, _ chr: GATTCharacteristicID?, started: Double,
                     bytes: Data? = nil, error: Error? = nil, note: String? = nil) async {
        let now = await logger.elapsed()
        var attError: Int?
        var errorNote: String?
        if let error {
            if case GATTError.att(let code) = error { attError = Int(code) }
            errorNote = String(describing: error)
        }
        await logger.log(TranscriptEntry(
            t: now, op: op,
            service: chr?.service.bluetoothDescription,
            char: chr?.characteristic.bluetoothDescription,
            bytes: bytes?.hexString,
            attError: attError,
            latencyMs: (now - started) * 1000,
            note: errorNote ?? note))
    }
}
