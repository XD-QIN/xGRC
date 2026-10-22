import CameraKit
import Foundation

/// Where fixes come from: Core Location on a device, a simulated walk for the
/// Demo camera and tests (architecture doc § Geotag defaults).
public protocol LocationSource: Sendable {
    func authorization() async -> LocationAuthorization
    /// Asks for *While Using* permission if it was never asked; returns the result.
    func requestAuthorization() async -> LocationAuthorization
    /// Starts updates (and, on a device, the background activity session).
    /// The stream ends when `stop()` is called, or when location access is
    /// taken away (check `authorization()` then).
    func start() async -> AsyncStream<GeoFix>
    func stop() async
}

public enum LocationAuthorization: Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
    /// Allowed, but Precise Location is off: fixes are kilometres wide and
    /// never pass the accuracy limit.
    case reducedAccuracy
}

/// Accepts or rejects fixes by the architecture doc's geotag rules: horizontal accuracy within the
/// limit, no older than the brand's maximum age, and never replacing a recent
/// good fix with one more than 3× worse inside the validity window.
public struct FixFilter: Sendable {
    public var accuracyLimit: Double
    public var maximumAge: Duration
    public var worseFactor: Double

    public private(set) var best: GeoFix?

    public init(accuracyLimit: Double = 50, maximumAge: Duration = .seconds(30), worseFactor: Double = 3) {
        self.accuracyLimit = accuracyLimit
        self.maximumAge = maximumAge
        self.worseFactor = worseFactor
    }

    /// Offers a new fix; returns `true` when it became the current best.
    @discardableResult
    public mutating func offer(_ fix: GeoFix, now: Date) -> Bool {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= accuracyLimit,
              isFresh(fix, now: now) else { return false }
        if let best, isFresh(best, now: now), fix.horizontalAccuracy > best.horizontalAccuracy * worseFactor {
            return false
        }
        best = fix
        return true
    }

    /// The best fix if it is still young enough to send.
    public func current(now: Date) -> GeoFix? {
        guard let best, isFresh(best, now: now) else { return nil }
        return best
    }

    public mutating func reset() {
        best = nil
    }

    private func isFresh(_ fix: GeoFix, now: Date) -> Bool {
        let age = now.timeIntervalSince(fix.timestamp)
        return age <= maximumAge.inSeconds && age >= -5
    }
}

extension Duration {
    /// The duration in seconds, as a `Double`.
    public var inSeconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
