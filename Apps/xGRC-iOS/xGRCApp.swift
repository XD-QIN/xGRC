import BLEKit
import DesignKit
import LocationKit
import Persistence
import SessionKit
import SharedState
import SwiftUI
import UIKit
import UserNotifications

@main
struct xGRCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.model)
                // Settings › Language: dates and numbers follow it, and the
                // whole tree is rebuilt so every string is looked up again.
                .environment(\.locale, delegate.model.language.locale)
                .id(delegate.model.language)
                // Settings › Appearance: System, Light or Dark; the tokens
                // carry both values. Signal colours mark status only, so
                // controls take the primary text colour (board 01 · Rules).
                .tint(Tally.Palette.textPrimary)
                .onChange(of: delegate.model.settings.appearance, initial: true) { _, appearance in
                    Self.apply(appearance)
                }
                // xgrc://session from the "Open xGRC" control.
                .onOpenURL { _ in delegate.model.showActiveSession() }
        }
    }

    /// Set on the window rather than with `preferredColorScheme`, which does
    /// not always return to the system appearance once set, and which the
    /// UIKit-resolved Tally colours would not see.
    @MainActor
    private static func apply(_ appearance: AppearanceSetting) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}

/// Builds the app's object graph once, at launch. The Core Bluetooth central
/// is created synchronously here with its fixed restore identifier, so state
/// restoration finds it after the system relaunches the app for a camera
/// event (architecture doc § Architecture, executor rule).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model: AppModel

    override init() {
        AppLanguage.activate()
        let central = CoreBluetoothCentral()
        let stores: Stores
        do {
            stores = try Stores.appDefault()
        } catch {
            stores = Stores(directory: FileManager.default.temporaryDirectory.appendingPathComponent("xGRC"),
                            secrets: KeychainSecretStore(service: "xGRC"))
        }
        let device = UIDevice.current
        let logger = TranscriptLogger(header: TranscriptHeader(
            startedAt: Date(),
            os: "\(device.systemName) \(device.systemVersion)",
            device: device.model,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"))
        // A Location prompt shows only with the app on screen (not from Siri or a relaunch).
        let location = CoreLocationSource(canPrompt: { UIApplication.shared.applicationState != .background })
        let coordinator = StoreScreens.coordinator(logger: logger)
            ?? SessionCoordinator(stores: stores, central: central, location: location, logger: logger)
        model = AppModel(coordinator: coordinator)
        super.init()
        IntentBridge.handler = model
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // A session never outlives the app, so neither does its Live Activity.
        model.liveActivity.endStale()
        UNUserNotificationCenter.current().delegate = self
        Task {
            await model.launch()
            await StoreScreens.stage(model)
        }
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        LiveActivityController.endAllBeforeExit()
        // The Shoot control reads this file: no session outlives the app.
        if let directory = AppGroup.directory { try? TileState().save(to: directory) }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Results that land while xGRC is frontmost but not active (Control
    /// Center pulled down) are still shown.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
