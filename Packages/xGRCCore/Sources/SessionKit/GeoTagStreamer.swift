import BLEKit
import CameraKit
import Foundation
import LocationKit

/// Geotag settings for one session (architecture doc § Geotag defaults).
public struct GeotagConfiguration: Hashable, Sendable {
    /// Push interval for push-model drivers; the driver's minimum still applies.
    public var interval: Duration = .seconds(5)
    /// Fixes less accurate than this are never sent.
    public var accuracyLimit: Double = 50
    /// A fix this far beyond its own accuracy from the last pushed fix is sent at once.
    public var movementThreshold: Double = 10
    /// After this long without a valid fix the page turns amber: photos untagged.
    public var noFixWarning: Duration = .seconds(30)
    /// Runs the driver's keep-alive (Sony `CC02`), which keeps the camera's screen on.
    public var keepAwake = false

    public init() {}
}

public enum GeotagStatus: Hashable, Sendable {
    case off
    case starting
    /// Started; no valid fix yet.
    case waitingForFix
    /// Pull-model cameras (Fujifilm): fixes are ready but the camera has not
    /// asked for one yet. It never asks while its own location sync is off.
    case waitingForCamera
    /// Fixes are reaching the camera.
    case tagging
    /// No valid fix for `noFixWarning`: photos are untagged.
    case noFix
    /// Valid fixes are ready but the camera refused the last pushes (its
    /// location link went off, or another device took it): photos are untagged.
    case cameraNotTagging
    /// The camera link is down; pushes resume on reconnect.
    case paused
    case failed(GeotagFailure)
}

public enum GeotagFailure: Hashable, Sendable {
    /// Location permission was refused.
    case locationDenied
    /// Location is allowed but Precise Location is off.
    case preciseLocationOff
    /// The camera's own location link setting is off (Sony `0x9D`).
    case cameraSettingOff
    /// Another phone, watch or app holds the camera's location lock (Sony `0x9F`).
    case busy
    /// This camera cannot take locations.
    case unsupported
    case other(String)
}

/// What the Geotag page shows.
public struct GeotagSnapshot: Hashable, Sendable {
    public var status: GeotagStatus = .off
    /// The latest fix from the location source, accepted or not.
    public var fix: GeoFix?
    public var startedAt: Date?
    public var lastPushAt: Date?
    public var pushes = 0
    public var failedPushes = 0
    /// The camera's own report of its location link, where it sends one.
    public var cameraLocationEnabled: Bool?

    public init() {}

    public var isActive: Bool {
        switch status {
        case .off, .failed: false
        default: true
        }
    }
}

/// Merges `LocationSource` fixes with the driver's location link: filters
/// fixes by the brand's rules, pushes on the interval and on movement (or, for
/// pull-model cameras, answers each request), pauses while the link is down,
/// and runs the keep-alive (architecture doc § Key abstractions).
/// Timing runs on an injected clock so tests are deterministic.
public actor GeoTagStreamer<C: Clock> where C.Duration == Duration {
    public let driver: any CameraDriver
    public let source: any LocationSource
    public let clock: C
    public private(set) var configuration: GeotagConfiguration

    private let now: @Sendable () -> Date
    private let zone: @Sendable () -> TimeZone
    private let rules: GeotagRules
    private var filter: FixFilter
    private var snapshot = GeotagSnapshot()
    private let broadcaster = Broadcaster<GeotagSnapshot>(replayLast: true)
    private let acceptedFixes = Broadcaster<GeoFix>()
    private var tasks: [Task<Void, Never>] = []
    private var running = false
    private var linkReady = true
    private var pushing = false
    /// How the camera takes fixes, from `startLocationLink`.
    private var mode: LocationLinkMode = .push
    /// A pull-model camera asked while no valid fix was ready; the next one answers it.
    private var requestPending = false
    private var lastPushedFix: GeoFix?
    private var lastPushInstant: C.Instant?
    private var lastValidFixInstant: C.Instant?
    private var startInstant: C.Instant?
    /// Pushes the camera refused since the last one it took.
    private var failedInARow = 0
    /// The last time a refused push enabled the camera's location link again.
    private var lastRelinkInstant: C.Instant?
    /// Refused pushes in a row before the page stops saying *Tagging*.
    static var refusalsBeforeWarning: Int { 2 }
    /// How often refused pushes enable the location link again.
    static var relinkInterval: Duration { .seconds(30) }

    public init(driver: any CameraDriver, source: any LocationSource, clock: C,
                configuration: GeotagConfiguration = .init(),
                now: @escaping @Sendable () -> Date = { Date() },
                zone: @escaping @Sendable () -> TimeZone = { TimeZone.current }) {
        self.driver = driver
        self.source = source
        self.clock = clock
        self.configuration = configuration
        self.now = now
        self.zone = zone
        self.rules = driver.geotagRules
        self.filter = FixFilter(accuracyLimit: configuration.accuracyLimit, maximumAge: driver.geotagRules.maximumFixAge)
        broadcaster.yield(snapshot)
    }

    public nonisolated func snapshots() -> AsyncStream<GeotagSnapshot> {
        broadcaster.stream()
    }

    public func currentSnapshot() -> GeotagSnapshot { snapshot }

    /// Every fix the filter accepts, for the session's GPS track.
    public nonisolated func validFixes() -> AsyncStream<GeoFix> {
        acceptedFixes.stream()
    }

    /// Asks for location permission, enables the camera's location link and
    /// starts streaming. Returns the status it settled on.
    @discardableResult
    public func start() async -> GeotagStatus {
        guard !running else { return snapshot.status }
        running = true
        filter.reset()
        lastPushedFix = nil
        lastPushInstant = nil
        lastValidFixInstant = nil
        requestPending = false
        failedInARow = 0
        lastRelinkInstant = nil
        let startedAt = now()
        update {
            $0 = GeotagSnapshot()
            $0.status = .starting
            $0.startedAt = startedAt
        }

        var authorization = await source.authorization()
        if authorization == .notDetermined {
            authorization = await source.requestAuthorization()
        }
        guard running else { return snapshot.status }
        guard authorization == .authorized else {
            await fail(Self.failure(for: authorization))
            return snapshot.status
        }
        do {
            mode = try await driver.startLocationLink()
        } catch {
            guard running else { return snapshot.status }
            await fail(Self.failure(for: error))
            return snapshot.status
        }
        guard running else {
            // Stopped while the link was being enabled: `stop()` ran before
            // the lock was taken, so release it now.
            await driver.stopLocationLink()
            return snapshot.status
        }

        let events = driver.events()
        let fixes = await source.start()
        guard running else {
            await source.stop()
            await driver.stopLocationLink()
            return snapshot.status
        }
        let started = clock.now
        startInstant = started
        update { $0.status = linkReady ? .waitingForFix : .paused }
        tasks = [
            Task { [weak self] in
                for await event in events {
                    switch event {
                    case .locationEnabled(let on): await self?.cameraReported(on)
                    case .locationRequested: await self?.cameraRequested()
                    default: break
                    }
                }
            },
            Task { [weak self] in
                for await fix in fixes { await self?.received(fix) }
                guard !Task.isCancelled else { return }
                await self?.fixesEnded()
            },
        ]
        if mode == .push {
            tasks.append(Task { [weak self] in await self?.pushLoop(from: started) })
        }
        if let keepAlive = driver.keepAlive {
            tasks.append(Task { [weak self] in await self?.keepAliveLoop(keepAlive, from: started) })
        }
        return snapshot.status
    }

    /// Stops streaming and releases the camera's location lock.
    public func stop() async {
        guard running || snapshot.status != .off else { return }
        running = false
        cancelTasks()
        await source.stop()
        await driver.stopLocationLink()
        update { $0.status = .off }
    }

    public func setConfiguration(_ configuration: GeotagConfiguration) {
        self.configuration = configuration
        filter.accuracyLimit = configuration.accuracyLimit
    }

    /// The camera link dropped: hold pushes until it is back.
    public func linkLost() {
        linkReady = false
        requestPending = false
        guard running else { return }
        update { $0.status = .paused }
    }

    /// The link is back and the driver re-enabled its location link.
    public func linkRestored() async {
        linkReady = true
        // The reconnect enabled the location link again; earlier refusals are moot.
        failedInARow = 0
        guard running else { return }
        refreshStatus()
        // A pull-model camera asks again on its own after a reconnect.
        if mode == .push {
            await push()
            refreshStatus()
        }
    }

    // MARK: Private

    private func received(_ fix: GeoFix) async {
        guard running else { return }
        update { $0.fix = fix }
        guard filter.offer(fix, now: now()) else { return }
        acceptedFixes.yield(fix)
        lastValidFixInstant = clock.now
        if mode == .pull {
            if requestPending, await push() { requestPending = false }
            refreshStatus()
            return
        }
        if let last = lastPushedFix {
            let moved = fix.distance(to: last)
            let sinceLast = lastPushInstant.map { $0.duration(to: clock.now) } ?? configuration.interval
            if moved >= configuration.movementThreshold + fix.horizontalAccuracy,
               sinceLast >= rules.minimumInterval {
                await push()
            }
        } else {
            await push()
        }
        refreshStatus()
    }

    /// Pushes on a fixed schedule from `start`, so a loop that reaches its
    /// sleep late does not shift every later push.
    private func pushLoop(from start: C.Instant) async {
        var next = start
        while running, !Task.isCancelled {
            next = Self.nextTick(after: next, every: max(configuration.interval, rules.minimumInterval), now: clock.now)
            do {
                try await clock.sleep(until: next, tolerance: nil)
            } catch {
                return
            }
            guard running else { return }
            await push()
            refreshStatus()
        }
    }

    private func keepAliveLoop(_ policy: KeepAlivePolicy, from start: C.Instant) async {
        var next = start
        while running, !Task.isCancelled {
            next = Self.nextTick(after: next, every: policy.interval, now: clock.now)
            do {
                try await clock.sleep(until: next, tolerance: nil)
            } catch {
                return
            }
            guard running, linkReady, configuration.keepAwake else { continue }
            try? await driver.send(policy.write)
        }
    }

    /// The next tick of a schedule; ticks missed while a push was slow are
    /// skipped rather than sent back to back.
    static func nextTick(after previous: C.Instant, every interval: Duration, now: C.Instant) -> C.Instant {
        guard interval > .zero else { return now }
        var next = previous.advanced(by: interval)
        while next < now { next = next.advanced(by: interval) }
        return next
    }

    /// The camera asked for a location (Fujifilm `01 00`).
    private func cameraRequested() async {
        guard running, mode == .pull else { return }
        requestPending = !(await push())
        refreshStatus()
    }

    /// Sends the current fix. `false` when nothing went out.
    @discardableResult
    private func push() async -> Bool {
        guard running, linkReady, !pushing, let fix = filter.current(now: now()) else { return false }
        pushing = true
        defer { pushing = false }
        let stamp = rules.stampsSendTime ? now() : fix.timestamp
        do {
            try await driver.updateLocation(fix, time: stamp, zone: zone())
            lastPushedFix = fix
            lastPushInstant = clock.now
            failedInARow = 0
            let pushedAt = now()
            update {
                $0.pushes += 1
                $0.lastPushAt = pushedAt
                $0.status = .tagging
            }
            return true
        } catch CameraError.transport(.disconnected) {
            linkLost()
        } catch CameraError.locationLinkOff {
            update {
                $0.failedPushes += 1
                $0.cameraLocationEnabled = false
            }
            failedInARow += 1
        } catch CameraError.unsupported {
            // The driver holds no location link (a re-enable on reconnect
            // failed, for one): enable it again.
            update { $0.failedPushes += 1 }
            failedInARow += 1
            await relinkIfDue()
        } catch {
            update { $0.failedPushes += 1 }
            failedInARow += 1
        }
        return false
    }

    /// After a few refused pushes in a row, enables the camera's location
    /// link again, at most every `relinkInterval`, so a lock another device
    /// held for a while recovers without a restart.
    private func relinkIfDue() async {
        guard mode == .push, failedInARow >= Self.refusalsBeforeWarning else { return }
        let instant = clock.now
        if let last = lastRelinkInstant, last.duration(to: instant) < Self.relinkInterval { return }
        lastRelinkInstant = instant
        _ = try? await driver.startLocationLink()
        // Stopped meanwhile: `stop()` released before this took the lock.
        if !running { await driver.stopLocationLink() }
    }

    private func cameraReported(_ enabled: Bool) {
        update { $0.cameraLocationEnabled = enabled }
        // The camera's link is on again: the next refused push re-enables at once.
        if enabled { lastRelinkInstant = nil }
    }

    /// Waiting, tagging or no fix, from how long ago the last valid fix came.
    private func refreshStatus() {
        guard running, linkReady else { return }
        if mode == .push, failedInARow >= Self.refusalsBeforeWarning, filter.current(now: now()) != nil {
            if snapshot.status != .cameraNotTagging { update { $0.status = .cameraNotTagging } }
            return
        }
        if filter.current(now: now()) != nil, lastPushedFix != nil {
            if snapshot.status != .tagging { update { $0.status = .tagging } }
            return
        }
        guard let since = lastValidFixInstant ?? startInstant else { return }
        let silent = since.duration(to: clock.now) >= configuration.noFixWarning
        var status: GeotagStatus = silent ? .noFix : (lastPushedFix == nil ? .waitingForFix : .tagging)
        if mode == .pull, lastPushedFix == nil, filter.current(now: now()) != nil {
            status = .waitingForCamera
        }
        if snapshot.status != status { update { $0.status = status } }
    }

    private func fail(_ failure: GeotagFailure) async {
        running = false
        cancelTasks()
        await source.stop()
        update { $0.status = .failed(failure) }
    }

    private func cancelTasks() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }

    private func update(_ change: (inout GeotagSnapshot) -> Void) {
        change(&snapshot)
        broadcaster.yield(snapshot)
    }

    /// The fix stream ended without `stop()`: location access was taken away.
    private func fixesEnded() async {
        guard running else { return }
        let authorization = await source.authorization()
        guard running, authorization != .authorized else { return }
        await fail(Self.failure(for: authorization))
    }

    static func failure(for authorization: LocationAuthorization) -> GeotagFailure {
        switch authorization {
        case .reducedAccuracy: .preciseLocationOff
        // Asked with the app in the background, where no prompt shows.
        case .notDetermined: .other("Open xGRC to allow Location.")
        case .denied, .restricted, .authorized: .locationDenied
        }
    }

    static func failure(for error: Error) -> GeotagFailure {
        switch error {
        case CameraError.locationLinkOff: .cameraSettingOff
        case CameraError.busy: .busy
        case CameraError.unsupported: .unsupported
        default: .other(describeFailure(error))
        }
    }
}
