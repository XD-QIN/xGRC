import CameraKit
import DesignKit
import Persistence
import SessionKit
import SwiftUI

/// The active camera, paged vertically. The pages follow the mode: Shutter
/// when it uses the remote, Geotag when it uses location, Settings always.
struct SessionView: View {
    enum Page: Hashable {
        case shutter
        case geotag
        case settings
    }

    @Environment(AppModel.self) private var model
    @State private var page: Page = Self.storePage
    @State private var confirmEnd = false

    var body: some View {
        TabView(selection: $page) {
            if model.mode.usesRemote {
                // Not under the End-session dialog, whose buttons Double Tap may mean.
                ShutterPage(doubleTapEnabled: page == .shutter && !confirmEnd)
                    .tag(Page.shutter)
            }
            if model.mode.usesGeotag {
                GeotagPage()
                    .tag(Page.geotag)
            }
            SettingsPage()
                .tag(Page.settings)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle(model.session.camera?.name ?? "Camera")
        .navigationBarTitleDisplayMode(.inline)
        // End session in the corner of every page, not only at the end of Settings.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { confirmEnd = true } label: {
                    Image(systemName: "stop.fill")
                }
                .tint(Tally.Palette.fault)
                .accessibilityLabel("End session")
            }
        }
        .confirmationDialog("End this session?", isPresented: $confirmEnd) {
            Button("End session", role: .destructive) { Task { await model.endSession() } }
        } message: {
            Text("The camera is released so another phone or watch can connect.")
        }
        .onAppear { page = firstPage(keeping: page) }
        .onChange(of: model.mode) { _, _ in page = firstPage(keeping: page) }
    }

    /// `.shutter`, unless an App Store screenshot run opens another page.
    private static var storePage: Page {
        switch StoreScreens.scene {
        case "geotag": .geotag
        case "controls": .settings
        default: .shutter
        }
    }

    /// Keeps the selected page if the mode still shows it, else the first one.
    private func firstPage(keeping current: Page) -> Page {
        switch current {
        case .shutter where model.mode.usesRemote, .geotag where model.mode.usesGeotag, .settings:
            return current
        default:
            return model.mode.usesRemote ? .shutter : .geotag
        }
    }
}

/// Link state, a Retry button when another device holds the camera or the
/// connect failed, and any session notice.
struct LinkLine: View {
    @Environment(AppModel.self) private var model

    private var isFailed: Bool {
        if case .failed? = model.session.link { return true }
        return false
    }

    var body: some View {
        VStack(spacing: Tally.Space.xxs) {
            HStack(spacing: Tally.Space.xxs) {
                LinkDot(model.linkIndicator, size: 8)
                Text(model.linkMessage ?? String(localized: model.linkIndicator.label.inAppLanguage))
                    .tallyText(.footnote)
                    .foregroundStyle(model.linkIndicator.labelColor)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            if model.session.link == .busy || isFailed {
                Button("Retry") { model.retry() }
                    .buttonStyle(.tally(.secondary, size: .small))
            }
            if let notice = model.noticeText {
                Text(notice)
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.pending)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ShutterPage: View {
    @Environment(AppModel.self) private var model
    @State private var showIntervalometer = false
    /// Wrist down with Always On: the screen is dimmed, and watchOS takes the
    /// first touch or a wrist raise to wake it. Neither a tap nor Double Tap
    /// reaches the app until then.
    @Environment(\.isLuminanceReduced) private var isDimmed
    let doubleTapEnabled: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Tally.Space.xs) {
                LinkLine()
                if model.intervalometer.isRunning {
                    IntervalometerStatus()
                } else {
                    ShutterButton(
                        appearance: model.appearance,
                        bulb: bulb,
                        bulbMode: model.bulbMode,
                        countdown: countdown,
                        confirmed: model.shutter.confirmed,
                        sent: model.shutter.sent,
                        isEnabled: model.isReady,
                        holdsShot: model.isLinkReturning,
                        // Not under the Timelapse sheet either.
                        doubleTapEnabled: doubleTapEnabled && !showIntervalometer,
                        onInput: { model.send($0) }
                    )
                    ShutterCaption(appearance: model.appearance, bulb: bulb, countdown: countdown)
                        .tallyText(.footnote)
                    // Confirmed and sent are shown separately wherever they can differ.
                    ShotCounter(confirmed: model.shutter.confirmed, sent: model.shutter.sent, words: false)
                    if let hint {
                        Text(hint)
                            .tallyText(.footnote)
                            .foregroundStyle(hintIsGesture ? Tally.Palette.textTertiary : Tally.Palette.pending)
                            .multilineTextAlignment(.center)
                    }
                    if let note = model.shutterNote {
                        Text(note)
                            .tallyText(.footnote)
                            .foregroundStyle(Tally.Palette.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    if model.settings.releaseDelaySeconds > 0 {
                        SettingReadout(title: "Delay", value: SettingText.delay(model.settings.releaseDelaySeconds))
                    }
                    if model.bulbMode {
                        SettingReadout(title: "Bulb", value: SettingText.bulb(model.settings.bulbSeconds))
                    }
                    Button {
                        showIntervalometer = true
                    } label: {
                        Label("Timelapse", systemImage: "timer")
                    }
                    .disabled(!model.isReady)
                }
            }
        }
        .sheet(isPresented: $showIntervalometer) { IntervalometerSheet() }
    }

    private var bulb: (since: Date, ends: Date)? {
        if case .bulbOpen(let since, let ends) = model.shutter.phase { return (since, ends) }
        return nil
    }

    private var countdown: (ends: Date, total: Duration)? {
        if case .countdown(let ends, let total) = model.shutter.phase { return (ends, total) }
        return nil
    }

    /// The hint is the gesture reminder unless something needs saying.
    private var hintIsGesture: Bool {
        !isDimmed && countdown == nil && bulb == nil && model.message == nil && model.shutter.hint == nil
    }

    private var hint: String? {
        if isDimmed { return String(localized: "Raise your wrist to shoot") }
        if countdown != nil { return String(localized: "tap = cancel") }
        if bulb != nil { return String(localized: "tap = close now") }
        if let message = model.message { return message }
        switch model.shutter.hint {
        // AF hold is hidden with Tap to shoot, and a single tap shoots then.
        case .focusAckTimedOut?:
            return model.tapToShoot ? String(localized: "No focus confirmation. Set the shutter button to start AF.")
                : String(localized: "No focus confirmation. Set the shutter button to start AF, or use AF hold.")
        case .noHalfPress?:
            return model.tapToShoot ? String(localized: "This camera has no half-press. Tap to shoot.")
                : String(localized: "This camera has no half-press. Double tap to shoot.")
        case .checkBulb?: return String(localized: "The link dropped during a bulb. Check the camera: the shutter may still be open.")
        case nil: return model.gestureHint
        }
    }
}

/// "Delay 10 s" or "Bulb 30 s" under the shutter while that setting is on.
private struct SettingReadout: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: Tally.Space.xxs) {
            Text(title).foregroundStyle(Tally.Palette.textTertiary)
            Text(value)
                .tallyText(.readoutS)
                .foregroundStyle(Tally.Palette.pending)
        }
        .tallyText(.footnote)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    @State private var confirmForget = false

    var body: some View {
        List {
            ModePicker()

            if model.mode.usesRemote {
                Section("Shutter") {
                    ShutterSettings()
                }
            }
            if model.mode.usesGeotag {
                Section("Geotag") {
                    GeotagSettings()
                    if model.session.camera?.driverID == SonyDriver.descriptor.id {
                        Toggle("Keep camera awake", isOn: Binding(
                            get: { model.activeRecord?.keepAwake ?? false },
                            set: { value in model.setKeepAwake(value) }))
                            .tint(Tally.Palette.confirmed)
                        Text("Keeps the camera's screen on so the first shots after it wakes are tagged.")
                            .tallyText(.footnote)
                            .foregroundStyle(Tally.Palette.textTertiary)
                    }
                }
            }
            Section("Connection") {
                ConnectionSettings()
            }

            Section {
                Button("End session") { Task { await model.endSession() } }
                    .fontWeight(.semibold)
                    .foregroundStyle(Tally.Palette.fault)
                Button("Forget camera", role: .destructive) { confirmForget = true }
            }
            AboutSection()
        }
        .confirmationDialog("Forget this camera?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) {
                guard let camera = model.session.camera else { return }
                Task { await model.forget(camera) }
            }
        } message: {
            Text("Also remove xGRC on the camera, and remove the camera in Settings › Bluetooth on this watch.")
        }
    }
}
