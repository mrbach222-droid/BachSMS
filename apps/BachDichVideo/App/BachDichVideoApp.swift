import SwiftUI

@main
struct BachDichVideoApp: App {
    @StateObject private var model = SessionModel()
    @StateObject private var pip = CaptionPiPController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView(model: model, pip: pip)
                .preferredColorScheme(.dark)
                .onAppear { pip.onPause = { model.pause($0) } }
                .onChange(of: scenePhase) { model.setForeground($0 != .background) }
                .onChange(of: model.snapshot) { _ in pip.update(model.displaySnapshot, settings: model.settings, previewOnly: model.previewOnly) }
                .onChange(of: model.previewOnly) { _ in pip.update(model.displaySnapshot, settings: model.settings, previewOnly: model.previewOnly) }
        }
    }
}
