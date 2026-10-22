import BLEKit
import CameraKit
import Foundation
import Persistence
@testable import SessionKit
import Testing

/// No button and no bulb is left held after a failed write, a lost link, a
/// disconnect or a stopped timelapse.
@Suite("Shutter safety")
struct ShutterSafetyTests {
    let clock = ManualClock()

    private func hex(_ camera: SimulatedPeripheral, _ chr: GATTCharacteristicID) async -> [String] {
        await camera.writes(to: chr).map(\.hexString)
    }

    private func canonRemote() async throws -> (SimulatedPeripheral, ShotSequencer<ManualClock>) {
        let camera = SimulatedPeripheral.canonRemote()
        let driver = CanonRemoteDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await camera.clearWrites()
        let sequencer = ShotSequencer(driver: driver, clock: clock)
        await sequencer.start()
        return (camera, sequencer)
    }

    private func nikon(bulbSeconds: Int = 60) async throws -> (SimulatedPeripheral, ShotSequencer<ManualClock>) {
        let camera = SimulatedPeripheral.nikonRemote()
        let driver = NikonRemoteDriver(transport: camera)
        let identity = try await driver.pair(
            Advertisement(peripheralID: UUID(), localName: "Z6_3", rssi: -50, manufacturerData: nil,
                          serviceUUIDs: [Nikon.service], isConnectable: true),
            client: .generate()) { _ in }
        try await driver.reconnect(identity: identity, client: .generate())
        await camera.clearWrites()
        var configuration = SequencerConfiguration()
        configuration.bulbDuration = .seconds(bulbSeconds)
        let sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()
        return (camera, sequencer)
    }

    private func bulbIsOpen(_ sequencer: ShotSequencer<ManualClock>) async -> Bool {
        await eventually {
            if case .bulbOpen = await sequencer.currentSnapshot().phase { return true }
            return false
        }
    }

    // MARK: Write errors

    @Test("A full press that fails still releases the half-press")
    func failedPressReleases() async throws {
        let (camera, sequencer) = try await canonRemote()
        await sequencer.handle(.focus)
        #expect(await eventually { await hex(camera, Canon.remoteControl) == ["4c"] })
        // The half-press is held; the full press fails.
        await camera.failNextWrite(to: Canon.remoteControl, with: .att(0x0E))
        await sequencer.handle(.shoot)
        await awaitIdle(sequencer)
        #expect(await hex(camera, Canon.remoteControl) == ["4c", "0c"])
        let after = await sequencer.currentSnapshot()
        #expect(after.lastResult == .failed(.transport(.att(0x0E))))
        #expect(after.sent == 0)
    }

    @Test("A full press that times out counts as sent but not confirmed, and is released")
    func timedOutPress() async throws {
        let (camera, sequencer) = try await canonRemote()
        await sequencer.handle(.focus)
        #expect(await eventually { await hex(camera, Canon.remoteControl) == ["4c"] })
        await camera.failNextWrite(to: Canon.remoteControl, with: .timeout)
        await sequencer.handle(.shoot)
        await awaitIdle(sequencer)
        #expect(await hex(camera, Canon.remoteControl) == ["4c", "0c"])
        let after = await sequencer.currentSnapshot()
        #expect(after.lastResult == .unconfirmed(.shutterTimedOut))
        #expect(after.sent == 1 && after.confirmed == 0)
    }

    // MARK: Bulb across a lost link

    @Test("Nikon Time: a bulb open when the link drops is closed on reconnect, before the release")
    func nikonBulbClosedOnReconnect() async throws {
        let (camera, sequencer) = try await nikon()
        await sequencer.handle(.toggleBulb)
        await clock.advance(by: .milliseconds(100), afterSleepers: 1)
        #expect(await bulbIsOpen(sequencer))
        #expect(await hex(camera, Nikon.remoteShutter) == ["02 02", "02 00"])

        await camera.dropLink()
        await sequencer.linkLost()
        await camera.restoreLink()
        await camera.clearWrites()
        await sequencer.linkRestored()
        await clock.advance(by: .milliseconds(100), afterSleepers: 1)
        await awaitIdle(sequencer)
        // Unlatch (a second press closes Time), then release all.
        #expect(await hex(camera, Nikon.remoteShutter) == ["02 02", "02 00", "02 00"])
        // Nikon cannot say whether that press closed the bulb or opened a new one.
        #expect(await sequencer.currentSnapshot().hint == .checkBulb)

        // Closed: the next reconnect only releases.
        await camera.clearWrites()
        await sequencer.linkRestored()
        await awaitIdle(sequencer)
        #expect(await hex(camera, Nikon.remoteShutter) == ["02 00"])
    }

    @Test("Nikon Time: a latch press that never went out is not followed by a second press")
    func nikonFailedLatch() async throws {
        let (camera, sequencer) = try await nikon()
        await camera.failNextWrite(to: Nikon.remoteShutter, with: .att(0x0E))
        await sequencer.handle(.toggleBulb)
        await awaitIdle(sequencer)
        #expect(await hex(camera, Nikon.remoteShutter) == ["02 00"])
        await camera.clearWrites()
        await sequencer.linkRestored()
        await awaitIdle(sequencer)
        #expect(await hex(camera, Nikon.remoteShutter) == ["02 00"])
    }

    @Test("Canon Smartphone: an open bulb is closed with 00 02 after a lost link")
    func canonSmartBulb() async throws {
        let camera = SimulatedPeripheral.canonSmart()
        let driver = CanonSmartDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        var configuration = SequencerConfiguration()
        configuration.bulbDuration = .seconds(30)
        let sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()
        await sequencer.handle(.shoot)
        #expect(await bulbIsOpen(sequencer))
        await sequencer.linkLost()
        await sequencer.linkRestored()
        await awaitIdle(sequencer)
        #expect(await hex(camera, Canon.shutter) == ["00 01", "00 02", "00 02"])
    }

    // MARK: Disconnect

    @Test("Every driver's disconnect releases its buttons; Fujifilm's as two writes")
    func disconnectReleases() async throws {
        let fujifilm = SimulatedPeripheral.fujifilm()
        let fujifilmDriver = FujifilmDriver(transport: fujifilm)
        try await fujifilmDriver.reconnect(identity: CameraIdentity(values: ["serial": Data([1, 2, 3, 4, 5])]),
                                           client: .generate())
        await fujifilm.clearWrites()
        await fujifilmDriver.disconnect()
        #expect(await hex(fujifilm, Fujifilm.shutter) == ["01 00", "00 00"])

        let ricoh = SimulatedPeripheral.ricoh()
        let ricohDriver = RicohDriver(transport: ricoh)
        try await ricohDriver.reconnect(identity: .bondOnly, client: .generate())
        await ricohDriver.disconnect()
        #expect(await hex(ricoh, Ricoh.operationRequest) == ["02 00"])

        let canon = SimulatedPeripheral.canonSmart()
        let canonDriver = CanonSmartDriver(transport: canon)
        try await canonDriver.reconnect(identity: .bondOnly, client: .generate())
        await canonDriver.disconnect()
        #expect(await hex(canon, Canon.shutter) == ["00 02"])
    }

    // MARK: Intervalometer

    @Test("Stopping a timelapse closes an open bulb frame at once")
    func stopClosesBulbFrame() async throws {
        var behavior = FakeCamera.Behavior.instant
        behavior.bulbMode = true
        let camera = FakeCamera(behavior: behavior)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        let sequencer = ShotSequencer(driver: driver, clock: clock)
        await sequencer.start()
        let intervalometer = Intervalometer(sequencer: sequencer, clock: clock)
        await intervalometer.start(IntervalometerPlan(intervalSeconds: 600, frames: 2, exposureSeconds: 300))
        #expect(await eventually { await camera.commands().map(\.hexString) == ["01 09", "01 08", "01 06"] })
        #expect(await camera.isBulbOpen)
        await intervalometer.stop()
        await awaitIdle(sequencer)
        #expect(await camera.commands().map(\.hexString)
                == ["01 09", "01 08", "01 06", "01 07", "01 09", "01 08", "01 06"])
        #expect(await camera.isBulbOpen == false)
        #expect(await intervalometer.currentSnapshot().state == .finished(.stopped))
    }

    @Test("Sony: a bulb open when the link drops is closed with a second press on reconnect")
    func sonyBulbClosedOnReconnect() async throws {
        var behavior = FakeCamera.Behavior.instant
        behavior.bulbMode = true
        let camera = FakeCamera(behavior: behavior)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        var configuration = SequencerConfiguration()
        configuration.bulbDuration = .seconds(60)
        let sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()
        await sequencer.handle(.toggleBulb)
        #expect(await bulbIsOpen(sequencer))
        #expect(await camera.isBulbOpen)

        await camera.dropLink()
        await sequencer.linkLost()
        await camera.restoreLink()
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await camera.clearReceived()
        await sequencer.linkRestored()
        await awaitIdle(sequencer)
        // Unlatch (a second press closes the bulb; the camera answers *ready*), then release all.
        #expect(await camera.commands().map(\.hexString) == ["01 07", "01 09", "01 08", "01 06", "01 08", "01 06"])
        #expect(await camera.isBulbOpen == false)

        // Closed: the next reconnect only releases.
        await camera.clearReceived()
        await sequencer.linkRestored()
        await awaitIdle(sequencer)
        #expect(await camera.commands().map(\.hexString) == ["01 08", "01 06"])
    }

    @Test("Sony: a bulb the camera ended during the drop is not left reopened by the reconnect")
    func sonyBulbEndedDuringDrop() async throws {
        var behavior = FakeCamera.Behavior.instant
        behavior.bulbMode = true
        let camera = FakeCamera(behavior: behavior)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        var configuration = SequencerConfiguration()
        configuration.bulbDuration = .seconds(60)
        let sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()
        await sequencer.handle(.toggleBulb)
        #expect(await bulbIsOpen(sequencer))

        // The camera lost power during the drop: its exposure ended.
        await camera.dropLink()
        await sequencer.linkLost()
        await camera.powerCycle()
        await camera.restoreLink()
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await camera.clearReceived()
        await sequencer.linkRestored()
        await awaitIdle(sequencer)
        // The close opened a new bulb (*shutter active*): a second close shuts it, then release all.
        #expect(await camera.commands().map(\.hexString)
                == ["01 07", "01 09", "01 08", "01 06", "01 07", "01 09", "01 08", "01 06", "01 08", "01 06"])
        #expect(await camera.isBulbOpen == false)
    }

    /// A Sony body whose acks wait on the test clock.
    private func clockedSony(_ behavior: FakeCamera.Behavior, bulbSeconds: Int? = nil) async throws
        -> (FakeCamera, ShotSequencer<ManualClock>) {
        let clock = self.clock
        let camera = FakeCamera(behavior: behavior, sleep: { duration in
            try await clock.sleep(until: clock.now.advanced(by: duration), tolerance: nil)
        })
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await camera.clearReceived()
        var configuration = SequencerConfiguration()
        configuration.bulbDuration = bulbSeconds.map { .seconds($0) }
        let sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()
        return (camera, sequencer)
    }

    @Test("Sony: a shutter ack after the 3 s window closes the bulb it reveals")
    func sonyLateBulbAck() async throws {
        var behavior = FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .milliseconds(3500))
        behavior.bulbMode = true
        let (camera, sequencer) = try await clockedSony(behavior, bulbSeconds: 60)
        await sequencer.handle(.toggleBulb)
        // The sequencer's 3 s shutter ack and the camera's late ack both wait on the clock.
        await clock.advance(by: .seconds(3), afterSleepers: 2)
        #expect(await eventually { await sequencer.currentSnapshot().lastResult == .unconfirmed(.shutterTimedOut) })
        #expect(await camera.isBulbOpen)
        // The late-bulb watch, the result display and the camera's ack.
        await clock.advance(by: .milliseconds(500), afterSleepers: 3)
        #expect(await eventually { await camera.isBulbOpen == false })
        await awaitIdle(sequencer)
        #expect(await camera.commands().map(\.hexString)
                == ["01 07", "01 09", "01 08", "01 06", "01 07", "01 09", "01 08", "01 06"])
    }

    @Test("A stop drops a queued bulb frame, even when an intent shot follows at once")
    func stopDropsQueuedFrame() async throws {
        let (camera, sequencer) = try await clockedSony(
            FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .seconds(1)))
        // A shot holds the queue until its shutter ack.
        await sequencer.handle(.shoot)
        let frame = Task { await sequencer.frame(focus: false, exposure: .seconds(30), readyTimeout: nil) }
        await settle()
        await sequencer.cancelFrameHold()
        let intent = Task {
            await sequencer.frame(focus: false, exposure: nil, readyTimeout: nil, stoppable: false)
        }
        await settle()
        await clock.advance(by: .seconds(1), afterSleepers: 2)
        #expect(await frame.value == .cancelled)
        // The intent's press, its ack timeout and the first shot's result display.
        await clock.advance(by: .seconds(1), afterSleepers: 3)
        #expect(await intent.value.isConfirmed)
        #expect(await camera.commands().map(\.hexString)
                == ["01 07", "01 09", "01 08", "01 06", "01 09", "01 08"])
    }

    @Test("A long exposure on a camera without bulb is a normal shot")
    func ricohLongExposure() async throws {
        let camera = SimulatedPeripheral.ricoh()
        let driver = RicohDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await camera.clearWrites()
        let sequencer = ShotSequencer(driver: driver, clock: clock)
        await sequencer.start()
        #expect(await sequencer.canHoldBulb == false)
        let result = await sequencer.frame(focus: false, exposure: .seconds(5), readyTimeout: nil)
        #expect(result.wasSent)
        #expect(await hex(camera, Ricoh.operationRequest) == ["01 01"])
    }
}
