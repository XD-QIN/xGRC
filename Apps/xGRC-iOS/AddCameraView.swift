import CameraKit
import DesignKit
import SessionKit
import SwiftUI

/// Pairing instructions above the scan results, placed by signal strength
/// when first seen (rows then stay put, so a tap pairs the body it meant),
/// with the brand decoded from the advertisement (product spec § iPhone /
/// iPad screens). The scan stops after 30 s or on leaving the screen.
struct AddCameraView: View {
    @Environment(AppModel.self) private var model
    @State private var pairing: DiscoveredCamera?

    var body: some View {
        List {
            Section("Put the camera in pairing mode") {
                ForEach(BrandText.pairingSteps) { brand in
                    DisclosureGroup(brand.brand) {
                        Text(brand.steps)
                            .tallyText(.footnote)
                            .foregroundStyle(Tally.Palette.textSecondary)
                    }
                }
            }
            #if XGRC_ACCESSORY_SETUP
            if #available(iOS 18.0, *) {
                Section {
                    AccessoryPickerButton()
                }
            }
            #endif
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
                    Button {
                        pairing = camera
                    } label: {
                        FoundCameraRow(camera: camera,
                                       connectedElsewhere: model.connectedElsewhere.contains(camera.id))
                    }
                    .disabled(!camera.match.isPairable && !model.connectedElsewhere.contains(camera.id))
                }
            }
            Section {
                Button("Scan again") { model.startScan() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tally.Palette.background)
        .navigationTitle("Add camera")
        .onAppear { model.startScan() }
        .onDisappear { model.stopScan() }
        .sheet(item: $pairing) { camera in
            PairingSheet(camera: camera)
        }
    }

}

private struct FoundCameraRow: View {
    let camera: DiscoveredCamera
    let connectedElsewhere: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.match.displayName)
                    .tallyText(.body)
                    .lineLimit(1)
                Text(status)
                    .tallyText(.footnote)
                    .foregroundStyle(camera.match.isPairable ? Tally.Palette.confirmed : Tally.Palette.textSecondary)
            }
            Spacer()
            // One badge: "SONY · −52 dBm" (board 02, caption caps).
            Text(verbatim: "\(camera.isDemo ? String(localized: "Demo") : brand) · \(rssi) dBm")
                .tallyText(.captionCaps)
                .monospacedDigit()
                .foregroundStyle(Tally.Palette.textTertiary)
        }
        .frame(minHeight: Tally.Target.shooting)
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        if connectedElsewhere {
            return String(localized: "Already connected to this iPhone. The maker's app may hold the camera's lock while it runs.")
        }
        return camera.match.isPairable ? String(localized: "Ready to pair") : String(localized: "Not in pairing mode")
    }

    /// With a true minus sign.
    private var rssi: String {
        let value = camera.advertisement.rssi
        return value < 0 ? "−\(-value)" : "\(value)"
    }

    private var brand: String {
        DriverRegistry.standard.driverType(id: camera.match.driverID)?.descriptor.displayName ?? ""
    }
}

/// Runs the pairing and shows each step. The system pairing dialog appears
/// on top when the camera asks for a bond.
private struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let camera: DiscoveredCamera
    /// The running attempt, first or *Try again*: it ends with the sheet.
    @State private var attempt: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: Tally.Space.m) {
                Text(camera.match.displayName)
                    .tallyText(.headline)
                switch model.pairing {
                case .running(let step)?:
                    ProgressView()
                    Text(label(for: step))
                        .tallyText(.body)
                        .multilineTextAlignment(.center)
                case .failed(let reason)?:
                    Text("The camera did not accept the pairing")
                        .tallyText(.body)
                        .foregroundStyle(Tally.Palette.fault)
                    Text(reason)
                        .tallyText(.footnote)
                        .foregroundStyle(Tally.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { start() }
                        .buttonStyle(.tally(.primary))
                case nil:
                    ProgressView()
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancelPairing()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { start() }
        .onDisappear { attempt?.cancel() }
    }

    /// Runs one attempt; a success closes the sheet, whichever attempt it was.
    private func start() {
        attempt?.cancel()
        attempt = Task {
            await model.pair(camera)
            if !Task.isCancelled, model.pairing == nil { dismiss() }
        }
    }

    private func label(for step: PairingStep) -> String {
        switch step {
        case .connecting: String(localized: "Connecting…")
        case .bonding: BrandText.bonding(driverID: camera.match.driverID)
        case .registering: String(localized: "Registering…")
        case .done: String(localized: "Paired")
        }
    }
}
