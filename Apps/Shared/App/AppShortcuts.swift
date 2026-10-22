import AppIntents
import CameraKit
import Foundation
import Persistence
import SessionKit

/// Siri phrases and the Shortcuts app (product spec § Shortcuts and Controls).
/// The watch's Action Button is not supported.
struct XGRCShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShootIntent(),
                    phrases: ["Shoot with \(.applicationName)", "Take a photo with \(.applicationName)"],
                    shortTitle: "Shoot", systemImageName: "camera.aperture")
        AppShortcut(intent: FocusIntent(),
                    phrases: ["Focus with \(.applicationName)"],
                    shortTitle: "Focus", systemImageName: "scope")
        AppShortcut(intent: StartGeotagIntent(),
                    phrases: ["Start geotagging with \(.applicationName)"],
                    shortTitle: "Start geotagging", systemImageName: "location")
        AppShortcut(intent: StopGeotagIntent(),
                    phrases: ["Stop geotagging with \(.applicationName)"],
                    shortTitle: "Stop geotagging", systemImageName: "location.slash")
    }
}

extension AppModel: CameraIntentHandler {
    func shoot() async throws -> String {
        do {
            switch try await coordinator.shootFromIntent() {
            case .result(let result):
                return Self.intentLine(for: result)
            case .countdown(let seconds):
                return String(localized: "Release delay: shooting in \(seconds) s.")
            case .bulb(let seconds, let delay) where delay > 0:
                return String(localized: "Bulb \(SettingText.bulb(seconds)), opening in \(delay) s.")
            case .bulb(let seconds, _):
                return String(localized: "Bulb open for \(SettingText.bulb(seconds)).")
            case .bulbClosed:
                return String(localized: "Bulb closed.")
            case .countdownCancelled:
                return String(localized: "Release delay cancelled. Nothing was taken.")
            case .stillRunning:
                return String(localized: "Sent. The camera has not answered yet.")
            }
        } catch {
            throw Self.intentError(error)
        }
    }

    func focus() async throws -> String {
        do {
            try await coordinator.focusFromIntent()
            return String(localized: "Focusing.")
        } catch {
            throw Self.intentError(error)
        }
    }

    func startGeotag() async throws -> String {
        guard isReady else {
            throw OpenAppToContinue(message: String(localized: "Open xGRC to connect the camera."))
        }
        switch await coordinator.startGeotag() {
        case .failed(let failure):
            // From the returned status, not `geotag`, whose snapshot may not have arrived yet.
            return geotagFailureText(failure)
        default:
            return String(localized: "Geotagging started.")
        }
    }

    func stopGeotag() async throws -> String {
        await coordinator.stopGeotag()
        return String(localized: "Geotagging stopped.")
    }

    /// Acknowledged, sent or not confirmed, as the product spec asks every intent to say.
    static func intentLine(for result: ShotResult) -> String {
        switch result {
        case .acknowledged: String(localized: "Taken. The camera confirmed it.")
        case .assumed: String(localized: "Sent. This camera does not confirm shots.")
        case .unconfirmed: String(localized: "Sent, not confirmed.")
        case .cancelled: String(localized: "Cancelled.")
        case .failed(let error): describe(error)
        }
    }

    /// No session or no link opens the app; anything else is said as is.
    static func intentError(_ error: Error) -> Error {
        switch error {
        case SessionError.noActiveSession, SessionError.notReady:
            OpenAppToContinue(message: String(localized: "Open xGRC to connect the camera."))
        default:
            IntentMessage(text: describe(error))
        }
    }
}

/// An error whose text the intent shows.
struct IntentMessage: Error, CustomLocalizedStringResourceConvertible {
    let text: String
    var localizedStringResource: LocalizedStringResource { "\(text)" }
}
