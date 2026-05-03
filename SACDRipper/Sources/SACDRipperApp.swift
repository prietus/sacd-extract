import SwiftUI

@main
struct SACDRipperApp: App {
    var body: some Scene {
        WindowGroup("SACD Ripper") {
            ContentView()
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}
