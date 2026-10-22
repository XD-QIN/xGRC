import DesignKit
import Persistence
import SwiftUI

/// App settings outside a session, from *Settings* on the camera list. The
/// same choices appear on a session's Settings page; both save to this
/// watch's settings file.
struct AppSettingsView: View {
    @Environment(AppModel.self) private var model

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
                }
            }
            Section("Connection") {
                ConnectionSettings()
            }
            Section {
                CrownRow(title: "Language", value: model.language.nativeName) {
                    CrownChoice(title: "Language", options: AppLanguage.allCases, current: model.language,
                                label: { $0.nativeName },
                                footnote: "English unless you choose another.") { model.setLanguage($0) }
                }
                Button("Show tips again") { model.showOnboarding = true }
            }
            AboutSection()
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Crown choice

/// A setting row: tap opens a `CrownChoice` for its value.
struct CrownRow<Destination: View>: View {
    let title: LocalizedStringKey
    let value: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value)
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Picks one value with the Digital Crown: the chosen value large, its
/// neighbours above and below (tap one to step to it), and a line about it.
/// Saved on leaving the screen, so turning past a value never applies it.
struct CrownChoice<Value: Hashable>: View {
    let title: LocalizedStringKey
    let options: [Value]
    let current: Value
    let label: (Value) -> String
    var detail: ((Value) -> String)?
    var footnote: LocalizedStringKey?
    let onCommit: (Value) -> Void

    @State private var index = 0.0
    @State private var loaded = false
    /// Focused on appear, so the Crown turns the value without a tap first.
    @FocusState private var crownFocused: Bool

    var body: some View {
        VStack(spacing: Tally.Space.xs) {
            neighbour(position - 1)
            Text(label(selected))
                .tallyText(.readoutL)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            neighbour(position + 1)
            if let detail {
                Text(detail(selected))
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote {
                Text(footnote)
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($index, from: 0, through: Double(max(choices.count - 1, 0)), by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .navigationTitle(title)
        .onAppear {
            crownFocused = true
            guard !loaded else { return }
            loaded = true
            index = Double(choices.firstIndex(of: current) ?? 0)
        }
        .onDisappear {
            if selected != current { onCommit(selected) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(label(selected)))
        .accessibilityHint("Turn the Digital Crown to change")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(to: position + 1)
            case .decrement: step(to: position - 1)
            @unknown default: break
            }
        }
    }

    /// The options, with the current value first if it is not one of them
    /// (a value saved by an older build), so opening and leaving changes nothing.
    private var choices: [Value] {
        options.contains(current) ? options : [current] + options
    }

    private var position: Int {
        min(max(Int(index.rounded()), 0), max(choices.count - 1, 0))
    }

    private var selected: Value { choices[position] }

    @ViewBuilder
    private func neighbour(_ at: Int) -> some View {
        if choices.indices.contains(at) {
            Text(label(choices[at]))
                .tallyText(.footnote)
                .foregroundStyle(Tally.Palette.textTertiary)
                .lineLimit(1)
                .onTapGesture { step(to: at) }
        } else {
            Text(" ").tallyText(.footnote)
        }
    }

    private func step(to target: Int) {
        guard choices.indices.contains(target) else { return }
        index = Double(target)
    }
}

// MARK: - Settings rows

/// Geotag only, Remote only, or both. Remembered on this watch.
struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            CrownRow(title: "Mode", value: model.mode.title) {
                CrownChoice(title: "Mode", options: SessionMode.allCases, current: model.mode,
                            label: { $0.title }, detail: { $0.detail }) { model.setMode($0) }
            }
        }
    }
}

/// Tap to shoot, release delay, bulb time, AF hold and focus hold.
struct ShutterSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Toggle("Tap to shoot", isOn: Binding(
            get: { model.settings.tapToShoot },
            set: { value in model.updateSettings { $0.tapToShoot = value } }))
            .tint(Tally.Palette.confirmed)
        Text(model.settings.tapToShoot
             ? LocalizedStringKey("One tap, or a hand Double Tap, focuses and then shoots. A haptic marks the shot.")
             : LocalizedStringKey("Tap focuses, double tap shoots. A hand Double Tap focuses and shoots."))
            .tallyText(.footnote)
            .foregroundStyle(Tally.Palette.textTertiary)
        CrownRow(title: "Release delay", value: SettingText.delay(model.settings.releaseDelaySeconds)) {
            ReleaseDelayView()
        }
        CrownRow(title: "Bulb", value: SettingText.bulb(model.settings.bulbSeconds)) {
            BulbTimeView()
        }
        // Focus is never held between taps with Tap to shoot.
        if !model.settings.tapToShoot {
            Toggle("AF hold", isOn: Binding(
                get: { model.settings.afHold },
                set: { value in model.updateSettings { $0.afHold = value } }))
                .tint(Tally.Palette.confirmed)
            CrownRow(title: "Focus hold", value: "\(model.settings.focusGraceSeconds) s") {
                CrownChoice(title: "Focus hold", options: Array(1...10), current: model.settings.focusGraceSeconds,
                            label: { "\($0) s" },
                            footnote: "How long a single tap keeps focus held.") { value in
                    model.updateSettings { $0.focusGraceSeconds = value }
                }
            }
        }
    }
}

/// The bulb time on two wheels, minutes and seconds: the Digital Crown turns
/// the selected wheel, a tap on the other wheel moves the Crown to it.
/// 0 min 0 s is Off; the longest is 99 min 59 s. Saved on leaving the screen.
struct BulbTimeView: View {
    private enum Wheel: Hashable {
        case minutes
        case seconds
    }

    @Environment(AppModel.self) private var model
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var loaded = false
    @FocusState private var wheel: Wheel?

    var body: some View {
        VStack(spacing: Tally.Space.xs) {
            HStack(spacing: Tally.Space.xxs) {
                Picker("Minutes", selection: $minutes) {
                    ForEach(0...AppSettings.maxBulbSeconds / 60, id: \.self) { Text("\($0)").tag($0) }
                }
                .focused($wheel, equals: .minutes)
                Text("min").tallyText(.footnote).foregroundStyle(Tally.Palette.textSecondary)
                Picker("Seconds", selection: $seconds) {
                    ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .focused($wheel, equals: .seconds)
                Text(verbatim: "s").tallyText(.footnote).foregroundStyle(Tally.Palette.textSecondary)
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 80)
            Text(total == 0 ? String(localized: "Off") : SettingText.bulb(total))
                .tallyText(.footnote)
                .foregroundStyle(total == 0 ? Tally.Palette.textTertiary : Tally.Palette.pending)
            Text("Set the camera to BULB. One tap opens the shutter, counts down and closes it. A tap during the bulb closes it early. 0 min 0 s turns it off.")
                .tallyText(.footnote)
                .foregroundStyle(Tally.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("Bulb")
        .onAppear {
            wheel = .minutes
            guard !loaded else { return }
            loaded = true
            minutes = model.settings.bulbSeconds / 60
            seconds = model.settings.bulbSeconds % 60
        }
        .onDisappear {
            let value = total
            if value != model.settings.bulbSeconds { model.updateSettings { $0.bulbSeconds = value } }
        }
    }

    private var total: Int { SettingText.bulbSeconds(minutes: minutes, seconds: seconds) }
}

/// How often a location is sent.
struct GeotagSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CrownRow(title: "Send location",
                 value: String(localized: "Every \(model.settings.geotagIntervalSeconds) s")) {
            CrownChoice(title: "Send location", options: Array(stride(from: 5, through: 60, by: 5)),
                        current: model.settings.geotagIntervalSeconds,
                        label: { String(localized: "Every \($0) s") },
                        footnote: "Also sent at once when you move.") { value in
                model.updateSettings { $0.geotagIntervalSeconds = value }
            }
        }
    }
}

/// Auto reconnect (on by default) and auto disconnect: Never, or 5–60
/// minutes (15 by default).
struct ConnectionSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Toggle("Auto reconnect", isOn: Binding(
            get: { model.settings.autoReconnect },
            set: { value in model.updateSettings { $0.autoReconnect = value } }))
            .tint(Tally.Palette.confirmed)
        Text(model.settings.autoReconnect
             ? LocalizedStringKey("Reconnects when the link drops, and reopens the last session when xGRC starts again.")
             : LocalizedStringKey("A dropped link ends the session."))
            .tallyText(.footnote)
            .foregroundStyle(Tally.Palette.textTertiary)
        CrownRow(title: "Auto disconnect", value: SettingText.autoDisconnect(model.settings.autoDisconnectMinutes)) {
            CrownChoice(title: "Auto disconnect", options: SettingText.autoDisconnectOptions,
                        current: model.settings.autoDisconnectMinutes, label: SettingText.autoDisconnect,
                        footnote: "Ends the session after this long with nothing done on the camera, or without reaching it. Geotagging and timelapses count as use.") { value in
                model.updateSettings { $0.autoDisconnectMinutes = value }
            }
        }
    }
}

/// Version and the app's links. A link opens in the watch's web view.
struct AboutSection: View {
    var body: some View {
        Section("About") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Version")
                Text(verbatim: AboutInfo.version)
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            ForEach(AboutInfo.links) { link in
                Link(destination: link.url) {
                    Label(link.title, systemImage: "arrow.up.right")
                }
            }
        }
    }
}

/// Off or 1–60 s on the Digital Crown.
struct ReleaseDelayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CrownChoice(title: "Release delay", options: Array(0...60), current: model.settings.releaseDelaySeconds,
                    label: SettingText.delay,
                    footnote: model.tapToShoot
                        ? "A tap, Double Tap or Shoot counts down, then fires. A tap during the countdown cancels."
                        : "Double tap or Shoot counts down, then fires. A tap during the countdown cancels.") { value in
            model.updateSettings { $0.releaseDelaySeconds = value }
        }
    }
}
