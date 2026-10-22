#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

/// The haptic vocabulary. Each acknowledged-shooting event has its own,
/// distinct haptic (product spec § Accessibility).
///
/// On watchOS, haptics play only while the app is active; the system drops them
/// in the background (product spec § Apple Watch). Callers fall back to a Live
/// Activity alert or a local notification there.
public enum TallyHaptic: Sendable {
    /// The camera confirmed focus.
    case focused
    /// The camera confirmed the exposure.
    case fired
    /// A press was sent and the camera did not confirm it.
    case notConfirmed
    /// A release-delay countdown reached zero. Plays once.
    case delayRelease
    /// The press went out on a camera that does not confirm shots (felt
    /// apart from the focus click). A confirmed shot plays `fired`.
    case released

    @MainActor
    public func play() {
        #if os(watchOS)
        let type: WKHapticType = switch self {
        case .focused: .click
        case .fired: .success
        case .notConfirmed: .failure
        case .delayRelease: .notification
        case .released: .start
        }
        WKInterfaceDevice.current().play(type)
        #elseif os(iOS)
        switch self {
        case .focused:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .fired:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .notConfirmed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .delayRelease:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .released:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #endif
    }
}
