// CLBackgroundActivitySession is iOS and watchOS only, so `swift test` on a Mac skips this file.
#if canImport(CoreLocation) && !os(macOS)
import CameraKit
import CoreLocation
import Foundation

/// Core Location fixes for geotagging (architecture doc § Geotag defaults):
/// `startUpdatingLocation()` with best accuracy and `.otherNavigation`,
/// background updates allowed, never auto-paused, inside a
/// `CLBackgroundActivitySession` so the process keeps running with the wrist
/// down and Core Location relaunches the app after a crash.
/// `CLLocationUpdate.liveUpdates()` is deliberately not used: its stationary
/// auto-pause can suspend the app on a tripod.
///
/// The manager lives on the main actor: Core Location delivers its delegate
/// callbacks on the run loop of the thread that created it.
@MainActor
public final class CoreLocationSource: NSObject, LocationSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<GeoFix>.Continuation?
    private var activity: CLBackgroundActivitySession?
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []
    /// The app is on screen: only then does a permission prompt show (and
    /// answer). The app passes its own check; the package cannot reach it.
    private let canPrompt: @MainActor () -> Bool

    public init(canPrompt: @escaping @MainActor () -> Bool = { true }) {
        self.canPrompt = canPrompt
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        #if os(iOS)
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        #endif
    }

    public func authorization() async -> LocationAuthorization {
        Self.map(manager)
    }

    public func requestAuthorization() async -> LocationAuthorization {
        let current = Self.map(manager)
        guard current == .notDetermined else { return current }
        // In the background (Siri, a relaunch) no prompt shows and no answer
        // comes: say so instead of waiting for good.
        guard canPrompt() else { return .notDetermined }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    public func start() async -> AsyncStream<GeoFix> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<GeoFix>.makeStream(bufferingPolicy: .bufferingNewest(8))
        self.continuation = continuation
        manager.allowsBackgroundLocationUpdates = true
        if activity == nil {
            activity = CLBackgroundActivitySession()
        }
        manager.startUpdatingLocation()
        return stream
    }

    public func stop() async {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        activity?.invalidate()
        activity = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: CLLocationManagerDelegate

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { location in
            GeoFix(latitude: location.coordinate.latitude,
                   longitude: location.coordinate.longitude,
                   altitude: location.verticalAccuracy > 0 ? location.altitude : nil,
                   horizontalAccuracy: location.horizontalAccuracy,
                   timestamp: location.timestamp)
        }
        MainActor.assumeIsolated {
            for fix in fixes { continuation?.yield(fix) }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient; the streamer's no-fix timer
        // covers every other case.
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.map(manager)
        MainActor.assumeIsolated {
            guard status != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            for waiter in waiters { waiter.resume(returning: status) }
            if status != .authorized {
                // Access was taken away mid-session (or Precise Location
                // turned off): end the stream, so the streamer says why.
                continuation?.finish()
                continuation = nil
            }
        }
    }

    private nonisolated static func map(_ manager: CLLocationManager) -> LocationAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        default: manager.accuracyAuthorization == .reducedAccuracy ? .reducedAccuracy : .authorized
        }
    }
}
#endif
