import CameraKit
import Foundation

/// A walk that moves about 1.4 m/s north-east from a start point, one fix per
/// interval. Backs the Demo camera's geotag session; tests drive it with
/// `emit(_:)` instead.
public actor SimulatedLocationSource: LocationSource {
    public static let defaultStart = GeoFix(latitude: 35.658581, longitude: 139.745433, altitude: 42,
                                            horizontalAccuracy: 5, timestamp: Date())

    private let start: GeoFix
    private let interval: Duration?
    private let now: @Sendable () -> Date
    private var continuation: AsyncStream<GeoFix>.Continuation?
    private var walker: Task<Void, Never>?
    private var step = 0
    public private(set) var authorizationValue: LocationAuthorization

    /// - Parameter interval: time between simulated fixes; `nil` emits only on `emit(_:)`.
    public init(start: GeoFix = SimulatedLocationSource.defaultStart, interval: Duration? = .seconds(1),
                authorization: LocationAuthorization = .authorized,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.start = start
        self.interval = interval
        self.authorizationValue = authorization
        self.now = now
    }

    public func authorization() async -> LocationAuthorization { authorizationValue }

    public func requestAuthorization() async -> LocationAuthorization {
        if authorizationValue == .notDetermined { authorizationValue = .authorized }
        return authorizationValue
    }

    public func setAuthorization(_ value: LocationAuthorization) {
        authorizationValue = value
    }

    public func start() async -> AsyncStream<GeoFix> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<GeoFix>.makeStream()
        self.continuation = continuation
        if let interval {
            walker = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.walk()
                    try? await Task.sleep(for: interval)
                }
            }
        }
        return stream
    }

    public func stop() async {
        walker?.cancel()
        walker = nil
        continuation?.finish()
        continuation = nil
    }

    /// Delivers one fix as Core Location would.
    public func emit(_ fix: GeoFix) {
        continuation?.yield(fix)
    }

    private func walk() {
        step += 1
        // ~1 m per 0.000009° of latitude.
        let metres = Double(step) * 1.4
        let fix = GeoFix(latitude: start.latitude + metres * 0.000009 * 0.7,
                         longitude: start.longitude + metres * 0.000011 * 0.7,
                         altitude: start.altitude, horizontalAccuracy: 5, timestamp: now())
        continuation?.yield(fix)
    }
}
