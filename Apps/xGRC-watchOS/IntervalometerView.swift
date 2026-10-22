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
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                CrownRow(title: "Every", value: seconds(plan.intervalSeconds)) {
                    CrownChoice(title: "Every", options: Self.intervals, current: plan.intervalSeconds,
                                label: seconds) { plan.intervalSeconds = $0 }
                }
                CrownRow(title: "Frames", value: framesText(plan.frames)) {
                    CrownChoice(title: "Frames", options: Self.frameCounts, current: plan.frames,
                                label: framesText) { plan.frames = $0 }
                }
                CrownRow(title: "Start after", value: waitText(plan.initialWaitSeconds)) {
                    CrownChoice(title: "Start after", options: Self.waits, current: plan.initialWaitSeconds,
                                label: waitText) { plan.initialWaitSeconds = $0 }
                }
                CrownRow(title: "Shutter open", value: exposureText(plan.exposureSeconds)) {
                    CrownChoice(title: "Shutter open", options: Self.exposures, current: plan.exposureSeconds,
                                label: exposureText,
                                footnote: "Camera uses the camera's own shutter speed.") { plan.exposureSeconds = $0 }
                }
                Toggle("Focus each frame", isOn: $plan.focusEachFrame)
                    .tint(Tally.Palette.confirmed)
                Text("Above 1 s the shutter runs as bulb; set the camera to BULB. Release delay does not apply.")
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textTertiary)
                Button("Start") {
                    model.startIntervalometer(plan)
                    dismiss()
                }
                .disabled(!model.isReady)
            }
            .navigationTitle("Timelapse")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            plan = model.settings.intervalometer
        }
    }

    // The Crown steps finely where small changes matter and coarsely above.
    static let intervals: [Double] = Array(1...59).map(Double.init)
        + Array(stride(from: 60.0, to: 600, by: 10)) + Array(stride(from: 600.0, through: 3600, by: 60))
    static let frameCounts: [Int?] = [nil]
        + (Array(1...99) + Array(stride(from: 100, to: 1000, by: 10)) + Array(stride(from: 1000, through: 9000, by: 500)))
            .map { Optional($0) }
    static let waits: [Double] = [0] + Array(stride(from: 5.0, to: 60, by: 5)) + Array(stride(from: 60.0, through: 3600, by: 60))
    static let exposures: [Double?] = [nil]
        + (Array(1...60).map(Double.init) + Array(stride(from: 70.0, through: 600, by: 10))).map { Optional($0) }

    private func framesText(_ frames: Int?) -> String {
        frames.map { "\($0)" } ?? String(localized: "Until stopped")
    }

    private func waitText(_ value: Double) -> String {
        value == 0 ? String(localized: "Now") : seconds(value)
    }

    private func exposureText(_ value: Double?) -> String {
        value.map(seconds) ?? String(localized: "Camera")
    }

    private func seconds(_ value: Double) -> String {
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
            Text(frameText(run))
                .tallyText(.readoutL)
                .accessibilityLabel(frameText(run).replacingOccurrences(of: "/", with: "of"))
            if case .waiting(let until) = run.state {
                Text(until, style: .timer)
                    .tallyText(.readoutS)
            } else if let next = run.nextFrameAt, run.state == .running {
                HStack(spacing: Tally.Space.xxs) {
                    // Not the onboarding button's "Next": its own key, so it translates as a label.
                    Text("Next frame")
                    Text(next, style: .timer)
                }
                .tallyText(.readoutS)
                .foregroundStyle(Tally.Palette.textSecondary)
            }
            ShotCounter(confirmed: run.confirmed, sent: run.sent, words: false)
            if run.missed > 0 || run.failed > 0 {
                Text("\(run.missed) missed · \(run.failed) failed")
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.pending)
            }
            Button("Stop", role: .destructive) { model.stopIntervalometer() }
                .buttonStyle(.tally(.destructive, size: .small, fullWidth: true))
        }
    }

    private func frameText(_ run: IntervalometerSnapshot) -> String {
        if let total = run.plan?.frames { return "\(run.frame)/\(total)" }
        return "\(run.frame)"
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
