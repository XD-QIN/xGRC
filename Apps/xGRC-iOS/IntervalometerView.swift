import DesignKit
import Persistence
import SessionKit
import SwiftUI

/// Sets up a timelapse (architecture doc § Intervalometer rules). Starts from the last
/// plan used; Start saves it for next time.
struct IntervalometerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var plan = IntervalometerPlan()
    @State private var runUntilStopped = false
    @State private var useExposure = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $plan.intervalSeconds, in: 1...3600, step: plan.intervalSeconds < 60 ? 1 : 10) {
                        LabeledContent("Every", value: Self.seconds(plan.intervalSeconds))
                    }
                    Toggle("Until stopped", isOn: $runUntilStopped)
                        .tint(Tally.Palette.confirmed)
                    if !runUntilStopped {
                        Stepper(value: Binding(get: { plan.frames ?? 100 }, set: { plan.frames = $0 }),
                                in: 1...9999, step: (plan.frames ?? 100) < 100 ? 1 : 10) {
                            LabeledContent("Frames", value: "\(plan.frames ?? 100)")
                        }
                    }
                    Stepper(value: $plan.initialWaitSeconds, in: 0...3600, step: 5) {
                        LabeledContent("Start after",
                                       value: plan.initialWaitSeconds == 0 ? String(localized: "Now")
                                                                           : Self.seconds(plan.initialWaitSeconds))
                    }
                }
                Section {
                    Toggle("Set shutter-open time", isOn: $useExposure)
                        .tint(Tally.Palette.confirmed)
                    if useExposure {
                        Stepper(value: Binding(get: { plan.exposureSeconds ?? 2 }, set: { plan.exposureSeconds = $0 }),
                                in: 1...600, step: 1) {
                            LabeledContent("Shutter open", value: Self.seconds(plan.exposureSeconds ?? 2))
                        }
                    }
                    Toggle("Focus each frame", isOn: $plan.focusEachFrame)
                        .tint(Tally.Palette.confirmed)
                } footer: {
                    Text("Above 1 s the shutter runs as bulb; set the camera to BULB. Release delay does not apply.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tally.Palette.background)
            .navigationTitle("Intervalometer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        var final = plan
                        if runUntilStopped { final.frames = nil } else if final.frames == nil { final.frames = 100 }
                        if !useExposure { final.exposureSeconds = nil }
                        model.startIntervalometer(final)
                        dismiss()
                    }
                    .disabled(!model.isReady)
                }
            }
        }
        .onAppear {
            plan = model.settings.intervalometer
            runUntilStopped = plan.frames == nil
            useExposure = plan.exposureSeconds != nil
        }
    }

    static func seconds(_ value: Double) -> String {
        let whole = Int(value.rounded())
        if whole < 60 { return "\(whole) s" }
        return whole % 60 == 0 ? "\(whole / 60) min" : "\(whole / 60) min \(whole % 60) s"
    }
}

/// Shown in place of the shutter while a timelapse runs.
struct IntervalometerStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let run = model.intervalometer
        VStack(spacing: Tally.Space.xs) {
            Text(stateText(run.state))
                .tallyText(.captionCaps)
                .foregroundStyle(run.state == .paused ? Tally.Palette.pending : Tally.Palette.textSecondary)
            Text(run.plan?.frames.map { "\(run.frame) / \($0)" } ?? "\(run.frame)")
                .tallyText(.readoutL)
                .foregroundStyle(Tally.Palette.textPrimary)
            if case .waiting(let until) = run.state {
                Text(until, style: .timer).tallyText(.readoutS)
            } else if let next = run.nextFrameAt, run.state == .running {
                (Text("Next frame in ") + Text(next, style: .timer))
                    .tallyText(.readoutS)
                    .foregroundStyle(Tally.Palette.textSecondary)
            }
            if run.missed > 0 || run.failed > 0 {
                Text("\(run.missed) missed · \(run.failed) failed")
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.pending)
            }
            ShotCounter(confirmed: run.confirmed, sent: run.sent)
            Button("Stop timelapse", role: .destructive) { model.stopIntervalometer() }
                .buttonStyle(.tally(.destructive))
        }
        .frame(minHeight: Tally.Target.shutterPhone)
    }

    private func stateText(_ state: IntervalometerState) -> LocalizedStringKey {
        switch state {
        case .waiting: "Starting in"
        case .running: "Timelapse"
        case .paused: "Camera disconnected · frames missed"
        case .idle, .finished: ""
        }
    }
}
