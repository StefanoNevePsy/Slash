import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched from `swift run` (no bundle): show in Dock and take focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Updater.shared.checkInBackground()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct WorkspaceKey: FocusedValueKey { typealias Value = Workspace }

extension FocusedValues {
    var workspace: Workspace? {
        get { self[WorkspaceKey.self] }
        set { self[WorkspaceKey.self] = newValue }
    }
}

@main
struct SlashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            WindowRoot()
                .environment(store)
                .frame(minWidth: 800, minHeight: 480)
        }
        .windowToolbarStyle(.unified)
        .commands { SlashCommands() }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

struct WindowRoot: View {
    @Environment(AppStore.self) private var store
    @State private var workspace: Workspace?

    var body: some View {
        Group {
            if let workspace {
                ContentView(workspace: workspace)
                    .focusedSceneValue(\.workspace, workspace)
            } else {
                Color.clear
            }
        }
        .onAppear { if workspace == nil { workspace = Workspace(store: store) } }
    }
}

struct SlashCommands: Commands {
    @FocusedValue(\.workspace) private var workspace

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updater.shared.checkNow() }
        }
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                guard let w = workspace else { return }
                w.open(w.focusedPane.activeTab.url, newTab: true)
            }
            .keyboardShortcut("t")
            Button("Close Tab") { workspace?.closeActiveTab() }
                .keyboardShortcut("w")
            Button("Split Pane") { workspace?.split() }
                .keyboardShortcut("d")
        }
        CommandMenu("Go") {
            Button("Command Palette…") { workspace?.showPalette = true }
                .keyboardShortcut("k")
            Divider()
            Button("Back") { workspace?.focusedPane.activeTab.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { workspace?.focusedPane.activeTab.goForward() }
                .keyboardShortcut("]")
            Button("Enclosing Folder") { workspace?.focusedPane.activeTab.goUp() }
                .keyboardShortcut(.upArrow)
            Divider()
            Button("Home") { workspace?.open(FileManager.default.homeDirectoryForCurrentUser) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }
}

struct SettingsView: View {
    @AppStorage("autoUpdate") private var autoUpdate = true

    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: $autoUpdate)
            Text("Version \(Updater.currentVersion)").foregroundStyle(.secondary)
            Button("Check Now") { Updater.shared.checkNow() }
        }
        .padding(20)
        .frame(width: 360)
    }
}
