import BLEKit
@testable import CameraKit
import Foundation
import Testing

/// A transport whose single-packet write limit is set by the test. With a
/// response the limit is 512, as on iOS (long writes).
private struct ShortWrites: GATTTransport {
    let base: FakeCamera
    let limit: Int

    func discover(services: [UUID]) async throws -> [GATTService] { try await base.discover(services: services) }
    func read(_ chr: GATTCharacteristicID) async throws -> Data { try await base.read(chr) }
    func write(_ data: Data, to chr: GATTCharacteristicID) async throws { try await base.write(data, to: chr) }
    func writeWithoutResponse(_ data: Data, to chr: GATTCharacteristicID) async throws {
        try await base.writeWithoutResponse(data, to: chr)
    }
    func subscribe(_ chr: GATTCharacteristicID) async throws -> AsyncThrowingStream<Data, Error> {
        try await base.subscribe(chr)
    }
    func properties(of chr: GATTCharacteristicID) async -> CharacteristicProperties { await base.properties(of: chr) }
    func maximumWriteLength(withResponse: Bool) async -> Int { withResponse ? 512 : limit }
    func readRSSI() async throws -> Int { try await base.readRSSI() }
    func linkEvents() -> AsyncStream<LinkEvent> { base.linkEvents() }
    func disconnect() async { await base.disconnect() }
}

@Suite("Bluetooth robustness")
struct BluetoothRobustnessTests {
    @Test("Sony: a location start that fails after taking the lock releases it")
    func sonyLockReleasedOnFailure() async throws {
        let camera = FakeCamera(behavior: FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .zero))
        var behavior = await camera.behavior
        behavior.locationEnableRefused = true
        await camera.setBehavior(behavior)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await #expect(throws: CameraError.locationLinkOff) { try await driver.startLocationLink() }
        #expect(await camera.locationLock == 0)
    }

    @Test("Sony: a link that cannot take a whole DD11 packet in one write still starts (as a long write)")
    func sonyWriteLength() async throws {
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: ShortWrites(base: camera, limit: 23))
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        #expect(try await driver.startLocationLink() == .push)
        #expect(await camera.locationLock == 1)
        try await driver.updateLocation(GeoFix(latitude: 35.0, longitude: 139.0, altitude: 10,
                                                horizontalAccuracy: 5, timestamp: Date()),
                                        time: Date(), zone: TimeZone(identifier: "UTC")!)
        #expect(await camera.locationPackets().count == 1)
    }

    @Test("The transcript logs the write length")
    func writeLengthLogged() async throws {
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(), os: "test", device: "test",
                                                               appVersion: "0"))
        let transport = RecordingTransport(FakeCamera(), logger: logger)
        #expect(await transport.maximumWriteLength(withResponse: true) == 512)
        let notes = await logger.snapshot().compactMap(\.note)
        #expect(notes.contains("maximum write length with response: 512 bytes"))
    }

    @Test("Canon Smartphone: a cancelled location start stops waiting at once")
    func canonCancelledStart() async throws {
        let driver = CanonSmartDriver(transport: SimulatedPeripheral.canonSmart(gpsFromSmartphone: false),
                                      enableWindow: .seconds(30))
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        let start = Task { try await driver.startLocationLink() }
        try await Task.sleep(for: .milliseconds(50))
        let cancelledAt = ContinuousClock.now
        start.cancel()
        await #expect(throws: CancellationError.self) { try await start.value }
        #expect(cancelledAt.duration(to: .now) < .seconds(1))
    }
}
