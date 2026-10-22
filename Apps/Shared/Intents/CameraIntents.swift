import AppIntents
import Foundation

// Compiled into the watch app and its widget extension. The widget needs the
// intent types for its buttons and controls; only the app process can reach
// the camera, so `perform()` asks to continue in the app when it runs anywhere
// else (product spec § Apple Watch › Smart Stack tile).

/// What the intents call. The app registers its implementation at launch;
/// in the widget extension's process it stays `nil`.
@MainActor
protocol CameraIntentHandler: AnyObject {
    /// Fires the shutter and returns the line the intent says.
    func shoot() async throws -> String
    func focus() async throws -> String
    func startGeotag() async throws -> String
    func stopGeotag() async throws -> String
    /// A press from the Island or a control failed before any shot (no
    /// session, not connected): say so where the user pressed.
    func reportIntentFailure(_ error: Error)
}

extension CameraIntentHandler {
    func reportIntentFailure(_ error: Error) {}
}

@MainActor
enum IntentBridge {
    static weak var handler: (any CameraIntentHandler)?
}

/// An intent that needs the app: thrown by the handler when there is no
/// session or the camera is not connected, so the intent opens xGRC. Where
/// it cannot (the widget extension), its message is what the system shows.
struct OpenAppToContinue: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

private let openAppMessage = "Open xGRC to connect the camera."

extension AppIntent {
    @MainActor
    fileprivate func run(_ action: @MainActor (any CameraIntentHandler) async throws -> String) async throws -> String {
        guard let handler = IntentBridge.handler else {
            throw OpenAppToContinue(message: openAppMessage)
        }
        return try await action(handler)
    }
}

/// *Shoot*: focus, full press, and the camera's answer within 8 s.
struct ShootIntent: AppIntent {
    static let title: LocalizedStringResource = "Shoot"
    static let description = IntentDescription("Takes a photo on the connected camera and says whether the camera confirmed it.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let line = try await run { try await $0.shoot() }
            return .result(dialog: "\(line)")
        } catch let error as OpenAppToContinue {
            throw continueInApp(error)
        }
    }
}

/// *Focus*: the half-press, held for the focus hold time.
struct FocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Focus"
    static let description = IntentDescription("Half-presses the shutter on the connected camera.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let line = try await run { try await $0.focus() }
            return .result(dialog: "\(line)")
        } catch let error as OpenAppToContinue {
            throw continueInApp(error)
        }
    }
}

struct StartGeotagIntent: AppIntent {
    static let title: LocalizedStringResource = "Start geotagging"
    static let description = IntentDescription("Sends your location to the connected camera so photos are geotagged.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let line = try await run { try await $0.startGeotag() }
            return .result(dialog: "\(line)")
        } catch let error as OpenAppToContinue {
            throw continueInApp(error)
        }
    }
}

// `ForegroundContinuableIntent` is unavailable in iOS and watchOS app extensions, so the
// widget extensions (WIDGET_EXTENSION; the iPhone one shoots through
// `LiveActivityIntent`) leave it out and the intent shows the message.
#if WIDGET_EXTENSION
extension AppIntent {
    @MainActor
    fileprivate func continueInApp(_ error: OpenAppToContinue) -> Error { error }
}
#else
extension ShootIntent: ForegroundContinuableIntent {}
extension FocusIntent: ForegroundContinuableIntent {}
extension StartGeotagIntent: ForegroundContinuableIntent {}

extension ForegroundContinuableIntent {
    @MainActor
    fileprivate func continueInApp(_ error: OpenAppToContinue) -> Error {
        needsToContinueInForegroundError("\(error.message)")
    }
}
#endif

#if os(watchOS)
// On the watch only the app process holds the camera link, and the widget
// extension (Smart Stack tile, Shoot control) has none, so it
// could only say "Open xGRC". With `openAppWhenRun` the system opens xGRC and
// performs Shoot and Focus in the app's process (WidgetKit, Adding
// interactivity to widgets and Live Activities). It is deprecated in favour of
// `supportedModes` on watchOS 26, which says nothing about which process runs
// the intent, so the documented property stays until a device test shows the
// newer one also runs in the app.
@available(*, deprecated)
extension ShootIntent {
    static var openAppWhenRun: Bool { true }
}

@available(*, deprecated)
extension FocusIntent {
    static var openAppWhenRun: Bool { true }
}
#endif

struct StopGeotagIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop geotagging"
    static let description = IntentDescription("Stops sending your location to the camera.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let handler = IntentBridge.handler else {
            return .result(dialog: "Geotagging is not running.")
        }
        let line = try await handler.stopGeotag()
        return .result(dialog: "\(line)")
    }
}

/// The App Group container the app and the tile share. Holds only
/// `TileState.json`.
enum AppGroup {
    static var directory: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "XGRCAppGroup") as? String, !id.isEmpty else {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    static let tileKind = "xGRC.shutter"
    /// The iPhone's Shoot control (iOS 18+).
    static let shootControlKind = "xGRC.shoot.iphone"
}
