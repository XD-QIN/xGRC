import BLEKit
import DesignKit
import Persistence
import SwiftUI

/// Root: saved cameras, the Bluetooth banner, and *Add camera*.
struct CamerasView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            List {
                if model.bluetooth == .poweredOff || model.bluetooth == .unauthorized {
                    Text(model.bluetooth == .unauthorized ? "xGRC needs Bluetooth. Allow it in Settings › Privacy." : "Bluetooth is off")
                        .tallyText(.footnote)
                        .foregroundStyle(Tally.Palette.fault)
                }
                if let ended = model.endedText {
                    Text(ended)
                        .tallyText(.footnote)
                        .foregroundStyle(Tally.Palette.textSecondary)
                }
                ForEach(model.cameras) { camera in
                    Button {
                        model.open(camera)
                    } label: {
                        CameraRow(camera: camera, state: rowState(for: camera))
                    }
                }
                NavigationLink(value: AppModel.Route.addCamera) {
                    Label("Add camera", systemImage: "plus")
                }
                NavigationLink(value: AppModel.Route.tracks) {
                    Label("GPS tracks", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                }
                NavigationLink(value: AppModel.Route.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("Cameras")
            .navigationDestination(for: AppModel.Route.self) { route in
                switch route {
                case .addCamera: AddCameraView()
                case .session: SessionView()
                case .settings: AppSettingsView()
                case .tracks: TrackListView()
                }
            }
        }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView() }
        .task { await model.reload() }
    }

    private func rowState(for camera: CameraRecord) -> LinkIndicator {
        model.session.camera?.id == camera.id ? model.linkIndicator : .saved
    }
}

struct CameraRow: View {
    let camera: CameraRecord
    let state: LinkIndicator

    var body: some View {
        HStack(spacing: Tally.Space.xs) {
            LinkDot(state)
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.name)
                    .tallyText(.body)
                    .lineLimit(1)
                Text(state.label)
                    .tallyText(.footnote)
                    .foregroundStyle(state.labelColor)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
