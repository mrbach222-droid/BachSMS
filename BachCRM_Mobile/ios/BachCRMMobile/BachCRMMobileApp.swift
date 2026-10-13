import SwiftUI

@main
struct BachCRMMobileApp: App {
    @StateObject private var store = CareStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}