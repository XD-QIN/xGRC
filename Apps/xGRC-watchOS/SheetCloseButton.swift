import DesignKit
import SwiftUI

extension View {
    /// Replaces a sheet's system close button. The system one takes the app's
    /// tint, which is near-white (`Tally.Palette.textPrimary`), so its white
    /// cross sat on a white disc. This one is a white cross on the raised
    /// grey. Needs a navigation container around the sheet's content.
    func sheetCloseButton(action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: action) {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                        .foregroundStyle(Tally.Palette.textPrimary)
                }
                .tint(Tally.Palette.raised)
            }
        }
    }
}
