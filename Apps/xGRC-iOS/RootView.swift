import BLEKit
import DesignKit
import Persistence
import SwiftUI
import UIKit

/// iPhone: one navigation stack. iPad: the camera list in a sidebar and the
/// session beside it (product spec § Features › iPad).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    CameraList()
                } detail: {
                    NavigationStack {
                        detail(for: model.path.last)
                    }
                    // A new route starts a fresh stack: screens pushed from the
                    // old one (Geotagging, Settings) do not stay on top of it.
                    .id(model.path.last)
                }
            } else {
                NavigationStack(path: $model.path) {
                    CameraList()
                        .navigationDestination(for: AppModel.Route.self) { detail(for: $0) }
                }
            }
        }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView() }
        .onChange(of: scenePhase, initial: true) { _, phase in model.scenePhaseChanged(phase) }
    }

    @ViewBuilder
    private func detail(for route: AppModel.Route?) -> some View {
        switch route {
        case .addCamera?: AddCameraView()
        case .session?: SessionView()
        case .settings?: SettingsView()
        case .tracks?: TrackListView()
        case nil:
            ContentUnavailableView("No camera open", systemImage: "camera",
                                   description: Text("Choose a camera, or add one."))
        }
    }
}

/// Saved cameras with live state, the Bluetooth banner, and the way in to
/// *Add camera* and *Settings*.
struct CameraList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.bluetooth == .poweredOff || model.bluetooth == .unauthorized {
                TallyBanner(.fault,
                            title: Text(model.bluetooth == .unauthorized ? "Bluetooth not allowed" : "Bluetooth is off"),
                            message: Text(model.bluetooth == .unauthorized
                                          ? "Allow it in Settings › Privacy & Security › Bluetooth."
                                          : "xGRC needs Bluetooth to reach your camera.")) {
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.tally(.primary, size: .small))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
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
            Button {
                model.path = [.addCamera]
            } label: {
                Label("Add camera", systemImage: "plus")
            }
            Button {
                model.path = [.tracks]
            } label: {
                Label("GPS tracks", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tally.Palette.background)
        .navigationTitle("Cameras")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.path = [.settings]
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .refreshable { await model.reload() }
        .task { await model.reload() }
    }

    private func rowState(for camera: CameraRecord) -> LinkIndicator {
        model.session.camera?.id == camera.id ? model.linkIndicator : .saved
    }
}

struct CameraRow: View {
    let camera: CameraRecord
    let state: LinkIndicator

    /// Board 04 · Link state: dot, name over a brand badge, and the state word
    /// on the right. Quiet states (Saved, Off) are regular weight.
    var body: some View {
        HStack(spacing: Tally.Space.s) {
            LinkDot(state)
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.name)
                    .tallyText(.headline)
                    .foregroundStyle(Tally.Palette.textPrimary)
                    .lineLimit(1)
                if let brand = camera.isDemo ? String(localized: "Demo") : BrandText.brandName(driverID: camera.driverID) {
                    Text(brand)
                        .tallyText(.captionCaps)
                        .foregroundStyle(Tally.Palette.textTertiary)
                }
            }
            Spacer(minLength: Tally.Space.xs)
            Text(state.label)
                .tallyText(.subheadline)
                .fontWeight(state == .saved || state == .off ? .regular : .semibold)
                .foregroundStyle(state.labelColor)
        }
        .frame(minHeight: Tally.Target.shooting)
        .accessibilityElement(children: .combine)
    }
}
