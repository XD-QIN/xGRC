import SwiftUI
import WidgetKit

@main
struct XGRCWidgets: WidgetBundle {
    init() {
        AppLanguage.activate()
    }

    // The widget bundle builder takes `if #available` without an `else`.
    var body: some Widget {
        SessionLiveActivity()
        if #available(iOS 18.2, *) {
            ShootControl()
        }
    }
}
