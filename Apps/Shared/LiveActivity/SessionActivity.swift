#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import SharedState

// Compiled into the iPhone app and its widget extension (product spec § Dynamic
// Island / Live Activity). The widget draws the activity; only the app
// process updates it and performs its intents.

struct SessionActivityAttributes: ActivityAttributes {
    typealias ContentState = SharedState.ActivityState

    /// When this activity was requested; the system ends it after 8 hours.
    var startedAt: Date
}

/// The Island's shutter and the iPhone Shoot control. A `LiveActivityIntent`
/// runs `perform()` in the app process, so the press reaches the live
/// Bluetooth link without opening the app.
struct ShootLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Shoot"
    static let description = IntentDescription("Takes a photo on the connected camera.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // The result reaches the Island as a content update, with an alert
        // on failure. A press that fails before any shot (no session, not
        // connected) produces no shutter update, so it is reported here.
        do {
            _ = try await IntentBridge.handler?.shoot()
        } catch {
            IntentBridge.handler?.reportIntentFailure(error)
        }
        return .result()
    }
}

/// The iPhone Shoot control's one action. A control's template cannot branch
/// on its value, so one intent serves both states: with a camera connected it
/// shoots in the app process, with none it opens xGRC. iOS 18.2 is where
/// `.result()` and `.result(opensIntent:)` share a type.
@available(iOS 18.2, *)
struct ShootControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Shoot"
    static let isDiscoverable = false

    @Parameter(title: "Connected")
    var connected: Bool

    init() {}

    init(connected: Bool) {
        self.connected = connected
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard connected else {
            return .result(opensIntent: OpenURLIntent(URL(string: "xgrc://session")!))
        }
        do {
            _ = try await IntentBridge.handler?.shoot()
        } catch is OpenAppToContinue {
            // The control's value was stale (the app was killed, or the link
            // dropped): open xGRC instead of doing nothing.
            return .result(opensIntent: OpenURLIntent(URL(string: "xgrc://session")!))
        } catch {
            IntentBridge.handler?.reportIntentFailure(error)
        }
        return .result()
    }
}
#endif
