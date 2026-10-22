import CameraKit
import DesignKit
import LocationKit
import MapKit
import SessionKit
import SwiftUI

/// Geotagging: map, numbers, interval, and Start/Stop (product spec § iPhone /
/// iPad screens). The location session keeps running with the phone locked.
struct GeotagView: View {
    @Environment(AppModel.self) private var model
    /// Follows the fix until the user pans or zooms the map.
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        let geotag = model.geotag
        List {
            Section {
                Map(position: $position, interactionModes: [.zoom, .pan]) {
                    if let fix = geotag.fix {
                        let coordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
                        MapCircle(center: coordinate, radius: max(fix.horizontalAccuracy, 5))
                            .foregroundStyle(Tally.Palette.location.opacity(0.2))
                        Marker("Your location", systemImage: "camera", coordinate: coordinate)
                            .tint(Tally.Palette.location)
                    }
                }
                .frame(height: 220)
                .listRowInsets(EdgeInsets())
                .onAppear { if let fix = geotag.fix { position = Self.region(for: fix) } }
                .onChange(of: model.geotag.fix) { _, fix in
                    guard let fix, !position.positionedByUser else { return }
                    position = Self.region(for: fix)
                }
            }
            Section {
                // Numbers that change while you watch them are monospaced
                // readouts; the accuracy is a location readout (board 01).
                LabeledContent("Accuracy") {
                    Text(geotag.fix.map { "±\(Int($0.horizontalAccuracy.rounded())) m" } ?? "—")
                        .tallyText(.readoutS)
                        .foregroundStyle(accuracyColor(geotag.fix))
                }
                LabeledContent("Last push") {
                    Group {
                        if let last = geotag.lastPushAt { Text(last, style: .relative) } else { Text("—") }
                    }
                    .tallyText(.readoutS)
                }
                LabeledContent("Pushes") { Text("\(geotag.pushes)").tallyText(.readoutS) }
                if let altitude = geotag.fix?.altitude {
                    LabeledContent("Altitude") { Text("\(Int(altitude.rounded())) m").tallyText(.readoutS) }
                }
                Picker("Interval", selection: Binding(
                    get: { model.settings.geotagIntervalSeconds },
                    set: { value in model.updateSettings { $0.geotagIntervalSeconds = value } })) {
                    ForEach(Array(stride(from: 5, through: 60, by: 5)), id: \.self) { Text("\($0) s").tag($0) }
                }
                Toggle("Live Activity", isOn: Binding(
                    get: { model.settings.liveActivity },
                    set: { value in model.updateSettings { $0.liveActivity = value } }))
                    .tint(Tally.Palette.confirmed)
            } footer: {
                if let message = model.geotagMessage {
                    Text(message.text)
                        .foregroundStyle(message.isFault ? Tally.Palette.fault : Tally.Palette.pending)
                } else if model.session.camera?.driverID == SonyDriver.descriptor.id {
                    Text("Sony bodies older than the α7 IV pause location while Bluetooth Rmt Ctrl is On. Choose Geotag only in Settings › Mode and turn Bluetooth Rmt Ctrl off.")
                }
            }
            Section {
                Group {
                    if geotag.isActive {
                        Button("Stop geotagging", role: .destructive) { model.stopGeotag() }
                            .buttonStyle(.tally(.destructive, fullWidth: true))
                    } else {
                        Button("Start geotagging") { model.startGeotag() }
                            .buttonStyle(.tally(.primary, fullWidth: true))
                            .disabled(!model.isReady)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tally.Palette.background)
        .navigationTitle("Geotagging")
    }

    private static func region(for fix: GeoFix) -> MapCameraPosition {
        .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
            latitudinalMeters: 600, longitudinalMeters: 600))
    }

    /// The location colour only for a fix good enough to send; a coarser one
    /// is never pushed, so it shows as a fault.
    private func accuracyColor(_ fix: GeoFix?) -> Color {
        guard let fix else { return Tally.Palette.textSecondary }
        let usable = fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= GeotagConfiguration().accuracyLimit
        return usable ? Tally.Palette.location : Tally.Palette.fault
    }
}
