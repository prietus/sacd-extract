import SwiftUI
import AppKit

@main
struct SACDRipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("SACD Ripper") {
            ContentView(ripController: appDelegate.ripController,
                        fixController: appDelegate.fixController)
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let ripController = RipController()
    let fixController = FixISOController()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ripController.isRunning {
            let alert = NSAlert()
            alert.messageText = "A rip is in progress"
            alert.informativeText = "Quitting will stop sacd_extract and leave the current output incomplete."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Stop Rip and Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        // Always run: also kills a `-P` probe that may still hold the
        // player's single connection.
        ripController.terminateForQuit()
        return .terminateNow
    }
}
