import AppKit
import SwiftUI

@main
struct FadeOutApp: App {
    @StateObject private var model = MixerModel()

    var body: some Scene {
        MenuBarExtra {
            MixerView(model: model)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .opacity(model.hasReducedSound ? 0.52 : 1)
                .accessibilityLabel("Fade Out")
        }
        .menuBarExtraStyle(.window)
    }
}
