import DesignKit
import Persistence
import SwiftUI

/// First launch: pick a mode, then two watch settings that keep a session
/// alive (product spec § Apple Watch › Runtime). Shown again from Settings.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        // The stack only hosts the close button's toolbar.
        NavigationStack {
            tips
                .sheetCloseButton { dismiss() }
        }
    }

    private var tips: some View {
        TabView(selection: $page) {
            ModeChoice { page = 1 }
                .tag(0)
            Tip(systemImage: "clock.arrow.circlepath",
                title: "Stay on xGRC",
                text: "On the watch, open Settings › General › Return to Clock › xGRC and choose After 1 hour, so xGRC is still there when you raise your wrist.") {
                page = 2
            }
            .tag(1)
            Tip(systemImage: "xmark.app",
                title: "Don't force-quit",
                text: "Leave xGRC running between shots. Force-quitting drops the camera and stops geotagging. Use End session instead.",
                button: "Done") {
                model.finishOnboarding()
            }
            .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct ModeChoice: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tally.Space.xs) {
                Text("What will you use xGRC for?")
                    .tallyText(.body)
                ForEach(SessionMode.allCases, id: \.self) { mode in
                    Button {
                        model.setMode(mode)
                        next()
                    } label: {
                        HStack {
                            Label(mode.title, systemImage: mode.systemImage)
                            Spacer()
                            if model.mode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Tally.Palette.confirmed)
                            }
                        }
                    }
                    .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                }
                Text("You can change this any time in Settings.")
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textTertiary)
            }
        }
    }
}

private struct Tip: View {
    let systemImage: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    var button: LocalizedStringKey = "Next"
    let action: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tally.Space.xs) {
                Image(systemName: systemImage)
                    .tallyText(.title3)
                    .foregroundStyle(Tally.Palette.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .tallyText(.body)
                Text(text)
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(button, action: action)
            }
        }
    }
}
