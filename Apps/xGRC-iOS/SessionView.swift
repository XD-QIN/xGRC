import CameraKit
import DesignKit
import Persistence
import SessionKit
import SwiftUI

/// The active camera (product spec § iPhone / iPad screens › Remote). The shutter
/// is the hero when the mode uses the remote; the geotag row opens the
/// Geotagging screen when it uses location. *End session* closes the page: at
/// the bottom of the screen when everything fits, after the last row when it
/// does not (a short screen, such as an iPhone SE or the iPhone Duo's outer
/// display), so it never covers a row.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showIntervalometer = StoreScreens.scene == "intervalometer"
    @State private var showGeotag = StoreScreens.scene == "geotag"
    @State private var confirmEnd = false

    /// iPad: the controls keep their phone sizes in a centred column.
    private static let columnWidth: CGFloat = 560

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: Self.columnWidth)
                    .padding(Tally.Space.m)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Tally.Palette.background)
        .navigationTitle(model.session.camera?.name ?? String(localized: "Camera"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(model.session.camera?.name ?? String(localized: "Camera"))
                        .tallyText(.headline)
                    if let brand = BrandText.brandName(driverID: model.session.camera?.driverID) {
                        Text(brand)
                            .tallyText(.captionCaps)
                            .foregroundStyle(Tally.Palette.textTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .confirmationDialog("End this session?", isPresented: $confirmEnd) {
            Button("End session", role: .destructive) { Task { await model.endSession() } }
        } message: {
            Text("The camera is released so another phone or watch can connect.")
        }
        .sheet(isPresented: $showIntervalometer) { IntervalometerSheet() }
        .navigationDestination(isPresented: $showGeotag) { GeotagView() }
    }

    private var content: some View {
        VStack(spacing: Tally.Space.l) {
            StatusStrip()
            // iPad: the session sits in the middle of the tall pane.
            if sizeClass == .regular { Spacer(minLength: 0) }
            if model.mode.usesRemote {
                remote
            }
            if model.mode.usesGeotag {
                GeotagRow()
            }
            // In Geotag only there is no shutter hint to carry an error.
            if !model.mode.usesRemote, let message = model.message {
                Text(message)
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.pending)
                    .multilineTextAlignment(.center)
            }
            if let message = model.noticeText {
                Text(message)
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.pending)
            }
            Spacer(minLength: 0)
            Button("End session", role: .destructive) { confirmEnd = true }
                .buttonStyle(.tally(.destructive, size: .small))
        }
    }

    @ViewBuilder
    private var remote: some View {
        VStack(spacing: Tally.Space.m) {
            if model.intervalometer.isRunning {
                IntervalometerStatus()
            } else {
                VStack(spacing: Tally.Space.s) {
                    ShutterButton(appearance: model.appearance, bulb: bulb, bulbMode: model.bulbMode,
                                  countdown: countdown,
                                  confirmed: model.shutter.confirmed, sent: model.shutter.sent,
                                  isEnabled: model.isReady, doubleTapEnabled: false, onInput: { model.send($0) })
                    ShutterCaption(appearance: model.appearance, bulb: bulb, countdown: countdown)
                        .tallyText(.title3)
                    Text(hint)
                        .tallyText(.subheadline)
                        .foregroundStyle(hintIsGesture ? Tally.Palette.textTertiary : Tally.Palette.pending)
                        .multilineTextAlignment(.center)
                    if let note = model.shutterNote {
                        Text(note)
                            .tallyText(.footnote)
                            .foregroundStyle(Tally.Palette.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, Tally.Space.xl)
            }
            HStack(spacing: Tally.Space.xs) {
                if model.capabilities.contains(.halfPress) {
                    Toggle("AF hold", isOn: Binding(
                        get: { model.settings.afHold },
                        set: { value in model.updateSettings { $0.afHold = value } }))
                        .toggleStyle(.tallyChip)
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    SettingChip(title: "Delay", value: SettingText.delay(model.settings.releaseDelaySeconds),
                                isOn: model.settings.releaseDelaySeconds > 0)
                }
                .buttonStyle(.plain)
                if model.hasBulb {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        SettingChip(title: "Bulb", value: SettingText.bulb(model.settings.bulbSeconds),
                                    isOn: model.bulbMode)
                    }
                    .buttonStyle(.plain)
                }
            }
            ShotCounter(confirmed: model.shutter.confirmed, sent: model.shutter.sent)
            Button {
                showIntervalometer = true
            } label: {
                HStack {
                    Text("Intervalometer")
                    Spacer()
                    Text(verbatim: "›").foregroundStyle(Tally.Palette.textTertiary)
                }
            }
            .buttonStyle(.tally(.secondary, fullWidth: true))
            .disabled(!model.isReady || model.intervalometer.isRunning)
        }
    }

    private var bulb: (since: Date, ends: Date)? {
        if case .bulbOpen(let since, let ends) = model.shutter.phase { return (since, ends) }
        return nil
    }

    private var countdown: (ends: Date, total: Duration)? {
        if case .countdown(let ends, let total) = model.shutter.phase { return (ends, total) }
        return nil
    }

    /// The hint line is the gesture reminder unless something needs saying.
    private var hintIsGesture: Bool {
        countdown == nil && bulb == nil && model.message == nil && model.shutter.hint == nil
    }

    private var hint: String {
        if countdown != nil { return String(localized: "Tap to cancel") }
        if bulb != nil { return String(localized: "Tap to close now") }
        if let message = model.message { return message }
        switch model.shutter.hint {
        case .focusAckTimedOut?:
            return String(localized: "The camera may be set to back-button AF; enable AF on the shutter button for focus confirmation.")
        case .noHalfPress?:
            return String(localized: "No focus control on this camera. Double tap to shoot.")
        case .checkBulb?:
            return String(localized: "The link dropped during a bulb. Check the camera: the shutter may still be open.")
        case nil:
            return model.gestureHint
        }
    }
}

/// Link and GPS chips at the top of the screen, and the banner when another
/// device holds the camera (board 05 and board 04 · Status strip).
private struct StatusStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Tally.Space.xs) {
            HStack(spacing: Tally.Space.xs) {
                TallyChip {
                    LinkDot(model.linkIndicator, size: 8)
                    Text(model.linkIndicator.label)
                }
                .accessibilityElement(children: .combine)
                if model.mode.usesGeotag, model.geotag.isActive {
                    TallyChip {
                        // The accuracy only while fixes reach the camera: the
                        // latest raw fix may be old or rejected.
                        if model.geotag.status == .tagging, let fix = model.geotag.fix {
                            Text(verbatim: Tally.Glyph.location).foregroundStyle(Tally.Palette.location)
                            Text("GPS")
                            Text(verbatim: "±\(Int(fix.horizontalAccuracy.rounded())) m")
                                .tallyText(.readoutS)
                        } else if model.geotag.status == .noFix || model.geotag.status == .cameraNotTagging {
                            Text(verbatim: Tally.Glyph.fault).foregroundStyle(Tally.Palette.fault)
                            Text("Not tagging")
                        } else {
                            Text(verbatim: Tally.Glyph.pending).foregroundStyle(Tally.Palette.pending)
                            Text("GPS searching")
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity)
            if model.session.link == .busy {
                TallyBanner(.busy,
                            title: Text("\(model.session.camera?.name ?? String(localized: "The camera")) is busy"),
                            message: model.linkMessage.map { Text($0) }) {
                    Button("Retry") { model.retry() }
                        .buttonStyle(.tally(.secondary, size: .small))
                }
            } else if let line = model.linkMessage {
                Text(line)
                    .tallyText(.footnote)
                    .foregroundStyle(model.linkIndicator.labelColor)
                    .multilineTextAlignment(.center)
                if case .failed? = model.session.link {
                    Button("Retry") { model.retry() }
                        .buttonStyle(.tally(.secondary, size: .small))
                }
            }
        }
    }
}

/// "Delay 10 s ›": opens Settings, where the release delay is set.
private struct SettingChip: View {
    let title: LocalizedStringKey
    let value: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: Tally.Space.xxs) {
            Text(title)
            Text(value)
                .tallyText(.readoutS)
                .foregroundStyle(isOn ? Tally.Palette.pending : Tally.Palette.textSecondary)
            Text(verbatim: "›")
        }
        .tallyText(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(Tally.Palette.textPrimary)
        .padding(.horizontal, Tally.Space.m)
        .frame(minHeight: Tally.Target.minimum)
        .background(Tally.Palette.raised, in: RoundedRectangle(cornerRadius: Tally.Radius.chip, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// "◎ Geotag · sending / 8 s ago · 142 pushes" with Stop, opening the
/// Geotagging screen (board 05).
private struct GeotagRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Tally.Space.s) {
            NavigationLink {
                GeotagView()
            } label: {
                HStack(spacing: Tally.Space.s) {
                    Text(verbatim: glyph)
                        .tallyText(.headline)
                        .foregroundStyle(glyphColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .tallyText(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Tally.Palette.textPrimary)
                        if model.geotag.isActive {
                            detail
                                .tallyText(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Tally.Palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if !model.geotag.isActive {
                        Text(verbatim: "›").foregroundStyle(Tally.Palette.textTertiary)
                    }
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            if model.geotag.isActive {
                Button("Stop") { model.stopGeotag() }
                    .buttonStyle(.tally(.destructive, size: .small))
            }
        }
        .padding(.leading, Tally.Space.m)
        .padding(.trailing, Tally.Space.xs)
        .frame(minHeight: Tally.Target.shooting)
        .background(Tally.Palette.surface, in: RoundedRectangle(cornerRadius: Tally.Radius.card, style: .continuous))
    }

    private var title: LocalizedStringKey {
        guard model.geotag.isActive else { return "Geotag · off" }
        return model.geotag.lastPushAt == nil ? "Geotag · waiting for GPS" : "Geotag · sending"
    }

    @ViewBuilder
    private var detail: some View {
        if let last = model.geotag.lastPushAt {
            Text("\(Text(last, style: .relative)) ago · \(SettingText.pushes(model.geotag.pushes))")
        } else {
            Text(SettingText.pushes(model.geotag.pushes))
        }
    }

    private var glyph: String {
        model.geotag.isActive && model.geotag.lastPushAt == nil ? Tally.Glyph.pending : Tally.Glyph.location
    }

    private var glyphColor: Color {
        guard model.geotag.isActive else { return Tally.Palette.textTertiary }
        return model.geotag.lastPushAt == nil ? Tally.Palette.pending : Tally.Palette.location
    }
}
