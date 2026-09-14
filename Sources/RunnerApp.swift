import SwiftUI

@main
struct RunnerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .statusBar(hidden: true)
        }
    }
}
