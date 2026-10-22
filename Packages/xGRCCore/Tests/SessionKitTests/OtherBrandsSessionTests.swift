import BLEKit
import CameraKit
import Foundation
import LocationKit
@testable import SessionKit
import Testing

/// The sequencer and the streamer on the Phase 5 drivers: brands with no
/// acks, Nikon's bulb-as-Time, Fujifilm's pull-model geotag.
@Suite("Other brands in a session")
struct OtherBrandsSessionTests {
    let clock = ManualClock()
    let base = Date(timeIntervalSince1970: 1_792_069_509)

    private let fujifilmIdentity = CameraIdentity(values: ["serial": Data([1, 2, 3, 4, 5])])

    private func shutterWrites(_ camera: SimulatedPeripheral, _ chr: GATTCharacteristicID) async -> [String] {
        await camera.writes(to: chr).map(\.hexString)
    }

    @Test("Fujifilm Shoot: half-press, a settle instead of a focus ack, a timed press, reported as sent")
    func fujifilmShoot() async throws {
        let camera = SimulatedPeripheral.fujifilm()
        let driver = FujifilmDriver(transport: camera)
        try await driver.reconnect(identity: fujifilmIdentity, client: .generate())
        let sequencer = ShotSequencer(driver: driver, clock: clock)
        await sequencer.start()

        await sequencer.handle(.shoot)
        await settle()
        #expect(await shutterWrites(camera, Fujifilm.shutter) == ["01 00", "03 00"])
        await clock.advance(by: .milliseconds(250), afterSleepers: 1)
        #expect(await eventually {
            await camera.writes(to: Fujifilm.shutter).map(\.hexString).suffix(2) == ["01 00", "02 00"]
        })
        await clock.advance(by: .milliseconds(100), afterSleepers: 1)
        #expect(await eventually { await sequencer.currentSnapshot().sent == 1 })
        await awaitIdle(sequencer)
        #expect(await shutterWrites(camera, Fujifilm.shutter)
                == ["01 00", "03 00", "01 00", "02 00", "01 00", "00 00", "01 00", "00 00"])
        let after = await sequencer.currentSnapshot()
        #expect(after.confirmed == 0)
        guard case .assumed = after.lastResult else {
            Issue.record("expected an assumed shot, got \(String(describing: after.lastResult))")
            return
        }
        #expect(after.hint == nil, "no focus-confirmation hint on a brand that never confirms focus")
    }

    @Test("Nikon: leaving the scene with bulb open closes it with a second press (Time)")
    func nikonTime() async throws {
        let camera = SimulatedPeripheral.nikonRemote()
        let driver = NikonRemoteDriver(transport: camera)
        let identity = try await driver.pair(
            Advertisement(peripheralID: UUID(), localName: "Z6_3", rssi: -50, manufacturerData: nil,
                          serviceUUIDs: [Nikon.service], isConnectable: true),
            client: .generate()) { _ in }
        try await driver.reconnect(identity: identity, client: .generate())
        var configuration = SequencerConfiguration()
        configuration.bulbDuration = .seconds(60)
        let sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()

        await sequencer.handle(.toggleBulb)
        await settle()
        await clock.advance(by: .milliseconds(100), afterSleepers: 1)
        #expect(await eventually {
            if case .bulbOpen = await sequencer.currentSnapshot().phase { return true }
            return false
        })
        #expect(await shutterWrites(camera, Nikon.remoteShutter) == ["02 02", "02 00"])

        await sequencer.handle(.sceneInactive)
        await settle()
        // The result display and the press hold.
        await clock.advance(by: .milliseconds(100), afterSleepers: 2)
        await awaitIdle(sequencer)
        #expect(await shutterWrites(camera, Nikon.remoteShutter) == ["02 02", "02 00", "02 02", "02 00"])
    }

    @Test("Ricoh has no bulb: a bulb time is ignored and a tap shoots")
    func ricohIgnoresBulb() async throws {
        let camera = SimulatedPeripheral.ricoh()
        let driver = RicohDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        var configuration = SequencerConfiguration()
        configuration.bulbDuration = .seconds(10)
        let sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()
        #expect(await sequencer.bulbMode == false)
        await sequencer.handle(.shoot)
        #expect(await eventually { await sequencer.currentSnapshot().sent == 1 })
    }

    @Test("Fujifilm geotag answers each request once, and a request before a fix waits for one")
    func pull() async throws {
        let camera = SimulatedPeripheral.fujifilm()
        let driver = FujifilmDriver(transport: camera)
        try await driver.reconnect(identity: fujifilmIdentity, client: .generate())
        let source = SimulatedLocationSource(interval: nil)
        let clock = self.clock
        let base = self.base
        let streamer = GeoTagStreamer(driver: driver, source: source, clock: clock,
                                      now: { base.addingTimeInterval(clock.now.offset.inSeconds) })
        func fix() -> GeoFix {
            GeoFix(latitude: 35.658581, longitude: 139.745433, altitude: 42, horizontalAccuracy: 5,
                   timestamp: base.addingTimeInterval(clock.now.offset.inSeconds))
        }
        @Sendable func packets() async -> Int { await camera.writes(to: Fujifilm.geotagPacket).count }

        #expect(await streamer.start() == .waitingForFix)

        // The camera asks before any fix: answered by the first one.
        await camera.notify(Fujifilm.locationRequest, on: Fujifilm.geotagRequest)
        await settle()
        #expect(await packets() == 0)
        await source.emit(fix())
        await settle()
        #expect(await packets() == 1)
        #expect(await streamer.currentSnapshot().status == .tagging)

        // Fixes alone never push, however far the interval runs.
        for _ in 0..<12 {
            await clock.advance(by: .seconds(1))
            await source.emit(fix())
            await settle()
        }
        #expect(await packets() == 1)

        await camera.notify(Fujifilm.locationRequest, on: Fujifilm.geotagRequest)
        #expect(await eventually { await packets() == 2 })
        await streamer.stop()
    }

    @Test("Fujifilm geotag with fixes but no request yet waits for the camera")
    func waitingForCamera() async throws {
        let camera = SimulatedPeripheral.fujifilm()
        let driver = FujifilmDriver(transport: camera)
        try await driver.reconnect(identity: fujifilmIdentity, client: .generate())
        let source = SimulatedLocationSource(interval: nil)
        let clock = self.clock
        let base = self.base
        let streamer = GeoTagStreamer(driver: driver, source: source, clock: clock,
                                      now: { base.addingTimeInterval(clock.now.offset.inSeconds) })
        await streamer.start()
        await source.emit(GeoFix(latitude: 35.66, longitude: 139.75, horizontalAccuracy: 5,
                                 timestamp: base))
        await settle()
        #expect(await streamer.currentSnapshot().status == .waitingForCamera)
        await streamer.stop()
    }
}
