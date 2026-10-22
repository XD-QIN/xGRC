import DesignKit
import Persistence
import SwiftUI

/// First launch: what xGRC is for, and two things that keep a session working.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SessionMode.allCases, id: \.self) { mode in
                        Button {
                            model.setMode(mode)
                        } label: {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.title).tallyText(.body)
                                        Text(mode.detail)
                                            .tallyText(.footnote)
                                            .foregroundStyle(Tally.Palette.textSecondary)
                                    }
                                } icon: {
                                    Image(systemName: mode.systemImage)
                                }
                                Spacer()
                                if model.mode == mode {
                                    Image(systemName: "checkmark").foregroundStyle(Tally.Palette.confirmed)
                                }
                            }
                        }
                        .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                    }
                } header: {
                    Text("What will you use xGRC for?")
                } footer: {
                    Text("You can change this any time in Settings.")
                }
                Section("Good to know") {
                    Label("Geotagging keeps running with the phone locked. The Live Activity shows it on the Lock Screen and in the Dynamic Island.",
                          systemImage: "location")
                    Label("Don't swipe xGRC away while you shoot. That drops the camera. Use End session instead.",
                          systemImage: "xmark.app")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tally.Palette.background)
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.finishOnboarding() }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
