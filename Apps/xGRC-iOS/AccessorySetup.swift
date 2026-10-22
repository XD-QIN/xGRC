#if XGRC_ACCESSORY_SETUP
import AccessorySetupKit
import CameraKit
import SwiftUI

/// The system accessory picker for Sony on iOS 18+ (product spec § Scope › Pairing).
/// Off by default: build with the `XGRC_ACCESSORY_SETUP` flag and the Info.plist
/// keys in the Phase 4 doc (Dev_Doc) to try it. Phase 6 checks whether adopting it limits
/// Core Bluetooth scanning for brands that cannot use the picker (Fujifilm
/// must pair on the app's own connection).
@available(iOS 18.0, *)
@MainActor
final class AccessorySetup {
    static let shared = AccessorySetup()

    private let session = ASAccessorySession()
    private var picked: ((UUID) -> Void)?

    private init() {
        session.activate(on: .main) { [weak self] event in
            MainActor.assumeIsolated {
                guard event.eventType == .accessoryAdded,
                      let id = event.accessory?.bluetoothIdentifier else { return }
                self?.picked?(id)
                self?.picked = nil
            }
        }
    }

    /// Shows the picker for Sony bodies; `picked` gets the peripheral the user chose.
    func showSonyPicker(picked: @escaping (UUID) -> Void) {
        self.picked = picked
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothCompanyIdentifier = ASBluetoothCompanyIdentifier(0x012D)
        let item = ASPickerDisplayItem(name: "Sony camera",
                                       productImage: UIImage(systemName: "camera") ?? UIImage(),
                                       descriptor: descriptor)
        session.showPicker(for: [item]) { _ in }
    }

    /// Forget: removes the bond the picker made.
    func remove(peripheralID: UUID) {
        guard let accessory = session.accessories.first(where: { $0.bluetoothIdentifier == peripheralID }) else {
            return
        }
        session.removeAccessory(accessory) { _ in }
    }
}

/// Opens the picker, then pairs the chosen camera through the normal flow.
@available(iOS 18.0, *)
struct AccessoryPickerButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            AccessorySetup.shared.showSonyPicker { id in
                model.pairPicked(peripheralID: id)
            }
        } label: {
            Label("Choose a Sony camera", systemImage: "camera.badge.ellipsis")
        }
    }
}
#endif
