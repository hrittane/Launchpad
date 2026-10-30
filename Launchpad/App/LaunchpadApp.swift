import AppKit
import SwiftUI

@main
struct LaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(viewModel: AppEnvironment.shared.viewModel)
                .frame(width: 520)
        }

        MenuBarExtra("Launchpad", systemImage: "square.grid.3x3.fill") {
            Button {
                AppEnvironment.shared.windowManager.toggle()
            } label: {
                Text("Show Launchpad", comment: "Status menu item")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            SettingsLink {
                Text("Preferences…", comment: "Status menu item")
            }

            Divider()

            Button {
                AppEnvironment.shared.viewModel.resetLayout()
            } label: {
                Text("Reset Layout", comment: "Status menu item")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit Launchpad", comment: "Status menu item")
            }
            .keyboardShortcut("q")
        }
    }
}
