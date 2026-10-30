import DesignKit
import SwiftUI

/// Settings › About › License: the full GNU GPL v3, in English. A lazy stack
/// of paragraphs, so the watch only lays out what is on screen.
struct LicenseView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(AboutInfo.licenseParagraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph)
                        .tallyText(.footnote)
                        .foregroundStyle(Tally.Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if AboutInfo.licenseParagraphs.isEmpty {
                    Link(destination: AboutInfo.licenseURL) {
                        Text(verbatim: "gnu.org/licenses/gpl-3.0")
                    }
                }
            }
            .padding()
        }
        #if os(iOS)
        .background(Tally.Palette.background)
        #endif
        .navigationTitle(Text(verbatim: AboutInfo.licenseName))
    }
}
