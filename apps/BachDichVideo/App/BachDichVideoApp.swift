import SwiftUI

@main
struct BachDichVideoApp: App {
    @StateObject private var model = SessionModel()
    @StateObject private var pip = CaptionPiPController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView(model: model, pip: pip, broadcast: model.broadcast)
                .preferredColorScheme(.dark)
                .onAppear { pip.onPause = { model.pause($0) } }
                .onChange(of: scenePhase) { _, phase in model.setForeground(phase != .background) }
                .onChange(of: model.snapshot) { pip.update(model.displaySnapshot, settings: model.settings, previewOnly: model.previewOnly) }
                .onChange(of: model.previewOnly) { pip.update(model.displaySnapshot, settings: model.settings, previewOnly: model.previewOnly) }
        }
    }
}
