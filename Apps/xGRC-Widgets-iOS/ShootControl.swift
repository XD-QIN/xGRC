import AppIntents
import SharedState
import SwiftUI
import WidgetKit

/// The iPhone Shoot control (iOS 18.2+): Control Center, the Lock Screen and
/// the Action Button. With a camera connected it shoots through the same
/// `LiveActivityIntent` path as the Island; with none it opens xGRC. On the watch
/// it is labelled "Shoot (phone)" (product spec § Shortcuts, Controls).
@available(iOS 18.2, *)
struct ShootControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AppGroup.shootControlKind, provider: SessionValueProvider()) { connected in
            ControlWidgetButton(action: ShootControlIntent(connected: connected)) {
                Label(connected ? "Shoot" : "Open xGRC", systemImage: connected ? "camera.aperture" : "camera")
            }
        }
        .displayName("Shoot (phone)")
        .description("Takes a photo on the connected camera.")
    }
}

/// A camera is connected in a mode that uses the remote, on a brand that can
/// shoot with the app in the background. Read from the state file the app
/// writes into the App Group.
@available(iOS 18.2, *)
struct SessionValueProvider: ControlValueProvider {
    var previewValue: Bool { true }

    func currentValue() async throws -> Bool {
        let state = AppGroup.directory.map(TileState.load(from:)) ?? TileState()
        return state.canShoot
    }
}
