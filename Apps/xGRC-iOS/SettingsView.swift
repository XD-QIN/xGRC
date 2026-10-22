import CameraKit
import DesignKit
import Persistence
import SessionKit
import SwiftUI

/// Settings on iPhone and iPad (product spec § iPhone / iPad screens › Settings).
/// Saved on this device only, like the watch's.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                    ForEach(SessionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Mode")
            } footer: {
                Text(model.mode.detail)
            }

            if model.mode.usesRemote {
                Section {
                    ReleaseDelaySlider()
                    BulbTimeField()
                    Toggle("AF hold", isOn: Binding(
                        get: { model.settings.afHold },
                        set: { value in model.updateSettings { $0.afHold = value } }))
                        .tint(Tally.Palette.confirmed)
                    Stepper(value: Binding(
                        get: { model.settings.focusGraceSeconds },
                        set: { value in model.updateSettings { $0.focusGraceSeconds = value } }), in: 1...10) {
                        LabeledContent("Focus hold", value: "\(model.settings.focusGraceSeconds) s")
                    }
                } header: {
                    Text("Shutter")
                } footer: {
                    Text("Bulb: type minutes and seconds, up to \(SettingText.bulbLimit); 0 is Off. Set the camera to BULB. One tap opens the shutter, counts down and closes it; a tap during the bulb closes it early. Off: tap focuses, double tap shoots.")
                }
            }

            if model.mode.usesGeotag {
                Section("Geotag") {
                    Picker("Send location", selection: Binding(
                        get: { model.settings.geotagIntervalSeconds },
                        set: { value in model.updateSettings { $0.geotagIntervalSeconds = value } })) {
                        ForEach(Array(stride(from: 5, through: 60, by: 5)), id: \.self) {
                            Text(String(localized: "Every \($0) s")).tag($0)
                        }
                    }
                    Toggle("Live Activity", isOn: Binding(
                        get: { model.settings.liveActivity },
                        set: { value in model.updateSettings { $0.liveActivity = value } }))
                        .tint(Tally.Palette.confirmed)
                    if model.session.camera?.driverID == SonyDriver.descriptor.id {
                        Toggle("Keep camera awake", isOn: Binding(
                            get: { model.activeRecord?.keepAwake ?? false },
                            set: { value in model.setKeepAwake(value) }))
                            .tint(Tally.Palette.confirmed)
                    }
                }
            }

            Section {
                Toggle("Auto reconnect", isOn: Binding(
                    get: { model.settings.autoReconnect },
                    set: { value in model.updateSettings { $0.autoReconnect = value } }))
                    .tint(Tally.Palette.confirmed)
                Picker("Auto disconnect", selection: Binding(
                    get: { model.settings.autoDisconnectMinutes },
                    set: { value in model.updateSettings { $0.autoDisconnectMinutes = value } })) {
                    ForEach(SettingText.autoDisconnectOptions, id: \.self) {
                        Text(SettingText.autoDisconnect($0)).tag($0)
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Auto reconnect: reconnects when the link drops, and reopens the last session when xGRC starts again. Off: a dropped link ends the session. Auto disconnect ends the session after this long with nothing done on the camera, or without reaching it; geotagging and timelapses count as use.")
            }

            Section("Appearance") {
                Picker("Appearance", selection: Binding(
                    get: { model.settings.appearance },
                    set: { value in model.updateSettings { $0.appearance = value } })) {
                    ForEach(AppearanceSetting.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                NavigationLink {
                    LanguageList()
                } label: {
                    LabeledContent("Language") { Text(verbatim: model.language.nativeName) }
                }
            }

            Section {
                Button("Show tips again") { model.showOnboarding = true }
            }

            // Only the open camera: after an auto disconnect the snapshot still names the ended one.
            if let camera = model.session.camera, model.session.link != .ended {
                Section {
                    Button("Forget \(camera.name)", role: .destructive) { confirmForget = true }
                }
            }

            Section("About") {
                LabeledContent("Version", value: AboutInfo.version)
                ForEach(AboutInfo.links) { link in
                    Link(destination: link.url) {
                        HStack {
                            Text(link.title).foregroundStyle(Tally.Palette.textPrimary)
                            Spacer()
                            if link.showsHost {
                                Text(verbatim: link.url.host() ?? "")
                                    .foregroundStyle(Tally.Palette.textTertiary)
                            }
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(Tally.Palette.textTertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tally.Palette.background)
        .navigationTitle("Settings")
        .confirmationDialog(Text("Forget \(model.session.camera?.name ?? String(localized: "this camera"))?"),
                            isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                guard let camera = model.session.camera else { return }
                Task { await model.forget(camera) }
            }
            Button("Open Bluetooth settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } message: {
            Text("Also remove xGRC on the camera, and remove the camera in Settings › Bluetooth, which also unpairs the maker's app.")
        }
    }
}

/// The bulb time typed as minutes and seconds, saved when the keyboard
/// closes: every keystroke would otherwise reconfigure the session. Seconds
/// past 59 carry into minutes; the total stops at 99 min 59 s.
private struct BulbTimeField: View {
    private enum Field: Hashable {
        case minutes
        case seconds
    }

    @Environment(AppModel.self) private var model
    /// Text, not numbers: a number field only updates its value when it
    /// commits, which can come after the keyboard has closed.
    @State private var minutes = ""
    @State private var seconds = ""
    @FocusState private var focus: Field?

    var body: some View {
        LabeledContent {
            HStack(spacing: Tally.Space.xs) {
                number($minutes, field: .minutes, label: "Bulb minutes")
                Text("min").foregroundStyle(Tally.Palette.textSecondary)
                number($seconds, field: .seconds, label: "Bulb seconds")
                Text(verbatim: "s").foregroundStyle(Tally.Palette.textSecondary)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bulb")
                if model.settings.bulbSeconds == 0 {
                    Text("Off")
                        .tallyText(.footnote)
                        .foregroundStyle(Tally.Palette.textTertiary)
                }
            }
        }
        .onAppear { load(model.settings.bulbSeconds) }
        .onChange(of: model.settings.bulbSeconds) { _, saved in
            if focus == nil { load(saved) }
        }
        .onChange(of: focus) { _, field in
            if field == nil { commit() }
        }
        // Back while a field is focused may tear the view down first.
        .onDisappear { commit() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private func number(_ text: Binding<String>, field: Field, label: LocalizedStringKey) -> some View {
        TextField("0", text: Binding(get: { text.wrappedValue },
                                     set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(4)) }))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .tallyText(.readoutS)
            .frame(width: 52)
            .focused($focus, equals: field)
            .accessibilityLabel(label)
    }

    private func load(_ total: Int) {
        minutes = total == 0 ? "" : String(total / 60)
        seconds = total == 0 ? "" : String(total % 60)
    }

    private func commit() {
        let total = SettingText.bulbSeconds(minutes: Int(minutes) ?? 0, seconds: Int(seconds) ?? 0)
        load(total)
        guard total != model.settings.bulbSeconds else { return }
        model.updateSettings { $0.bulbSeconds = total }
    }
}

/// The release delay, saved once the drag ends: every step of a drag would
/// otherwise write the settings file and reconfigure the session.
private struct ReleaseDelaySlider: View {
    @Environment(AppModel.self) private var model
    /// The value under the finger, kept until the saved value catches up;
    /// `nil` shows the saved one.
    @State private var draft: Double?
    @State private var editing = false

    private var seconds: Int { draft.map { Int($0.rounded()) } ?? model.settings.releaseDelaySeconds }

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("Release delay", value: SettingText.delay(seconds))
            Slider(value: Binding(
                get: { draft ?? Double(model.settings.releaseDelaySeconds) },
                set: { draft = $0 }), in: 0...60, step: 1) { isEditing in
                editing = isEditing
                if !isEditing { commit() }
            }
            .accessibilityLabel("Release delay")
            .accessibilityValue(SettingText.delay(seconds))
        }
        .onChange(of: model.settings.releaseDelaySeconds) { _, saved in
            if !editing, seconds == saved { draft = nil }
        }
        // A change that never ended an edit (an adjustable action) is saved on the way out.
        .onDisappear { if draft != nil { commit() } }
    }

    private func commit() {
        let value = seconds
        guard value != model.settings.releaseDelaySeconds else {
            draft = nil
            return
        }
        model.updateSettings { $0.releaseDelaySeconds = value }
    }
}

/// Settings › Language: each language in its own name, the chosen one ticked.
/// It applies at once; permission prompts follow the next time xGRC starts.
private struct LanguageList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        model.setLanguage(language)
                    } label: {
                        HStack {
                            Text(verbatim: language.nativeName)
                                .foregroundStyle(Tally.Palette.textPrimary)
                            Spacer()
                            if language == model.language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Tally.Palette.textPrimary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(language == model.language ? .isSelected : [])
                }
            } footer: {
                Text("English unless you choose another. System prompts, such as Bluetooth and Location permission, change the next time xGRC starts.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tally.Palette.background)
        .navigationTitle("Language")
    }
}
