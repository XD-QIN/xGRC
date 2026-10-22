import CameraKit
import DesignKit
import SessionKit
import SwiftUI

/// Scan, brand pairing instructions, and the cameras found. Tapping a camera
/// in pairing mode pairs it from the watch; the phone is never involved.
struct AddCameraView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Pairing mode") {
                ForEach(BrandText.pairingSteps) { brand in
                    NavigationLink(brand.brand) {
                        ScrollView {
                            Text(brand.steps)
                                .tallyText(.footnote)
                                .foregroundStyle(Tally.Palette.textSecondary)
                        }
                        .navigationTitle(brand.brand)
                    }
                }
            }
            Section("Found") {
                if model.discovered.isEmpty {
                    if model.isScanning {
                        HStack(spacing: Tally.Space.xs) {
                            ProgressView()
                            Text("Looking for cameras…").tallyText(.footnote)
                        }
                    } else {
                        Text("Scan stopped. No camera found.")
                            .tallyText(.footnote)
                            .foregroundStyle(Tally.Palette.textSecondary)
                    }
                }
                ForEach(model.discovered) { camera in
                    NavigationLink {
                        PairingView(camera: camera)
                    } label: {
                        FoundCameraRow(camera: camera)
                    }
                    .disabled(!camera.match.isPairable)
                }
            }
            Button("Scan again") { model.startScan() }
        }
        .navigationTitle("Add camera")
        .onAppear { model.startScan() }
        .onDisappear { model.stopScan() }
    }
}

private struct FoundCameraRow: View {
    let camera: DiscoveredCamera

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(camera.match.displayName)
                .tallyText(.body)
                .lineLimit(1)
            Text(camera.match.isPairable ? "Ready to pair · \(camera.advertisement.rssi) dBm" : "Not in pairing mode")
                .tallyText(.footnote)
                .foregroundStyle(camera.match.isPairable ? Tally.Palette.confirmed : Tally.Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Runs the pairing and shows each step. The system pairing dialog appears on
/// top when the camera asks for a bond.
struct PairingView: View {
    @Environment(AppModel.self) private var model
    let camera: DiscoveredCamera
    /// The running attempt, first or *Try again*: it ends with the view.
    @State private var attempt: Task<Void, Never>?

    var body: some View {
        VStack(spacing: Tally.Space.s) {
            Text(camera.match.displayName)
                .tallyText(.headline)
                .lineLimit(1)
            switch model.pairing {
            case .running(let step)?:
                ProgressView()
                Text(label(for: step))
                    .tallyText(.footnote)
                    .multilineTextAlignment(.center)
            case .failed(let reason)?:
                Text("The camera did not accept the pairing")
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.fault)
                    .multilineTextAlignment(.center)
                Text(reason)
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textSecondary)
                    .lineLimit(3)
                Button("Try again") { start() }
            case nil:
                ProgressView()
            }
        }
        .padding(.horizontal, Tally.Space.xs)
        .onAppear { start() }
        .onDisappear { attempt?.cancel() }
    }

    private func start() {
        attempt?.cancel()
        attempt = Task { await model.pair(camera) }
    }

    private func label(for step: PairingStep) -> String {
        switch step {
        case .connecting: "Connecting…"
        case .bonding: BrandText.bonding(driverID: camera.match.driverID)
        case .registering: "Registering…"
        case .done: "Paired"
        }
    }
}
