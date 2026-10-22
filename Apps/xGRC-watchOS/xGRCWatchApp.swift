import BLEKit
import DesignKit
import LocationKit
import Persistence
import SessionKit
import SwiftUI
import UserNotifications
import WatchKit

@main
struct xGRCWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CamerasView()
                .environment(delegate.model)
                // Settings › Language: dates and numbers follow it, and the
                // whole tree is rebuilt so every string is looked up again.
                .environment(\.locale, delegate.model.language.locale)
                .id(delegate.model.language)
                .preferredColorScheme(.dark)
                // Signal colours mark status only (board 01 · Rules).
                .tint(Tally.Palette.textPrimary)
                // Observed at the root, so wrist down and leaving the app
                // count on every screen, not only while a session is shown.
                .onChange(of: scenePhase, initial: true) { _, phase in delegate.model.scenePhaseChanged(phase) }
        }
    }
}

/// Builds the app's object graph once, at launch. The Core Bluetooth central
/// is created synchronously here with its fixed restore identifier, so state
/// restoration finds it (architecture doc § Architecture, executor rule).
@MainActor
final class AppDelegate: NSObject, WKApplicationDelegate {
    let model: AppModel

    override init() {
        AppLanguage.activate()
        let central = CoreBluetoothCentral()
        let stores: Stores
        do {
            stores = try Stores.appDefault()
        } catch {
            // Application Support is always creatable in the app's own
            // container; fall back to a temporary directory rather than crash.
            stores = Stores(directory: FileManager.default.temporaryDirectory.appendingPathComponent("xGRC"),
                            secrets: KeychainSecretStore(service: "xGRC"))
        }
        let device = WKInterfaceDevice.current()
        let logger = TranscriptLogger(header: TranscriptHeader(
            startedAt: Date(),
            os: "\(device.systemName) \(device.systemVersion)",
            device: device.model,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"))
        // A Location prompt shows only with the app on screen (not from Siri or a relaunch).
        let location = CoreLocationSource(canPrompt: { WKApplication.shared().applicationState != .background })
        let coordinator = StoreScreens.coordinator(logger: logger, rescanOnDisconnect: true)
            ?? SessionCoordinator(stores: stores, central: central, location: location,
                                  rescanOnDisconnect: true, logger: logger)
        model = AppModel(coordinator: coordinator)
        super.init()
        IntentBridge.handler = model
    }

    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        Task {
            await model.launch()
            await StoreScreens.stage(model)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// The wrist-down fallback (a shot, a timelapse end, a disconnect) is
    /// posted while xGRC is frontmost but inactive; without this the system
    /// shows nothing then.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
