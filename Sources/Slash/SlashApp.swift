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

    /// While typing in a text field the standard edit action goes to the text; otherwise it acts on files.
    private func fileOrText(_ textAction: Selector, _ fileAction: (Workspace) -> Void) {
        if Workspace.isEditingText {
            NSApp.sendAction(textAction, to: nil, from: nil)
        } else if let w = workspace {
            fileAction(w)
        }
    }

    private func go(_ url: URL) { workspace?.open(url) }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updater.shared.checkNow() }
        }

        // MARK: File
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                guard let w = workspace else { return }
                w.open(w.focusedPane.activeTab.url, newTab: true)
            }
            .keyboardShortcut("t")
            Button("New Folder") { workspace?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open") { fileOrText(#selector(NSResponder.moveToEndOfDocument(_:))) { $0.openSelection() } }
                .keyboardShortcut("o")
            Button("Open Selection") { fileOrText(#selector(NSResponder.moveToEndOfDocument(_:))) { $0.openSelection() } }
                .keyboardShortcut(.downArrow)
            Button("Close Tab") { workspace?.closeActiveTab() }
                .keyboardShortcut("w")
            Divider()
            Button("Get Info") { workspace?.getInfo() }
                .keyboardShortcut("i")
            Button("Rename") { workspace?.beginRename() }
            Button("Duplicate") { workspace?.duplicateSelection() }
                .keyboardShortcut("d")
            Button("Make Alias") { workspace?.makeAlias() }
                .keyboardShortcut("a", modifiers: [.command, .control])
            Button("Show Original") { workspace?.showOriginal() }
                .keyboardShortcut("r")
            Divider()
            Button("Move to Trash") { fileOrText(#selector(NSResponder.deleteToBeginningOfLine(_:))) { $0.trashSelection() } }
                .keyboardShortcut(.delete)
            Button("Eject") { workspace?.ejectSelection() }
                .keyboardShortcut("e")
            Divider()
            Button("Find") { workspace?.focusedPane.searchActive = true }
                .keyboardShortcut("f")
        }

        // MARK: Edit (works on files, or on text while typing)
        CommandGroup(replacing: .undoRedo) {
            Button(Workspace.isEditingText ? "Undo" : FileUndo.shared.undoTitle) {
                if Workspace.isEditingText {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else {
                    FileUndo.shared.undo(store: workspace?.store)
                }
            }
            .keyboardShortcut("z")
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x")
            Button("Copy") { fileOrText(#selector(NSText.copy(_:))) { $0.copySelection() } }
                .keyboardShortcut("c")
            Button("Paste") { fileOrText(#selector(NSText.paste(_:))) { $0.paste(move: false) } }
                .keyboardShortcut("v")
            Button("Move Item Here") { workspace?.paste(move: true) }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Button("Select All") {
                fileOrText(#selector(NSText.selectAll(_:))) { w in
                    let pane = w.focusedPane
                    pane.selection = Set(pane.activeTab.items.filter { !$0.isHidden }.map(\.url))
                }
            }
            .keyboardShortcut("a")
        }

        // MARK: View
        CommandGroup(before: .toolbar) {
            Button("as Icons") { workspace?.setViewMode(.icons) }
                .keyboardShortcut("1")
            Button("as List") { workspace?.setViewMode(.list) }
                .keyboardShortcut("2")
            Button("as Columns") { workspace?.setViewMode(.columns) }
                .keyboardShortcut("3")
            Divider()
            Button("Use Groups") { workspace?.toggleGroups() }
                .keyboardShortcut("0", modifiers: [.command, .control])
            Menu("Sort By") {
                Button("Name") { workspace?.sort(by: .name) }.keyboardShortcut("1", modifiers: [.command, .option, .control])
                Button("Kind") { workspace?.sort(by: .kind) }.keyboardShortcut("2", modifiers: [.command, .option, .control])
                Button("Date Last Opened") { workspace?.sort(by: .lastOpened) }.keyboardShortcut("3", modifiers: [.command, .option, .control])
                Button("Date Added") { workspace?.sort(by: .added) }.keyboardShortcut("4", modifiers: [.command, .option, .control])
                Button("Date Modified") { workspace?.sort(by: .modified) }.keyboardShortcut("5", modifiers: [.command, .option, .control])
                Button("Date Created") { workspace?.sort(by: .created) }
                Button("Size") { workspace?.sort(by: .size) }.keyboardShortcut("6", modifiers: [.command, .option, .control])
                Button("Tags") { workspace?.sort(by: .tags) }.keyboardShortcut("7", modifiers: [.command, .option, .control])
            }
            Menu("Group By") {
                Button("None") { workspace?.group(by: nil) }
                Button("Kind") { workspace?.group(by: .kind) }.keyboardShortcut("2", modifiers: [.command, .control])
                Button("Date Last Opened") { workspace?.group(by: .lastOpened) }.keyboardShortcut("3", modifiers: [.command, .control])
                Button("Date Added") { workspace?.group(by: .added) }.keyboardShortcut("4", modifiers: [.command, .control])
                Button("Date Modified") { workspace?.group(by: .modified) }.keyboardShortcut("5", modifiers: [.command, .control])
                Button("Date Created") { workspace?.group(by: .created) }
                Button("Size") { workspace?.group(by: .size) }.keyboardShortcut("6", modifiers: [.command, .control])
                Button("Tags") { workspace?.group(by: .tags) }.keyboardShortcut("7", modifiers: [.command, .control])
            }
            Button("Show View Options") { workspace?.focusedPane.showViewOptions = true }
                .keyboardShortcut("j")
            Button("Show/Hide Hidden Files") { workspace?.toggleHidden() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Divider()
            Button("Split Pane") { workspace?.split() }
                .keyboardShortcut("\\")
            Divider()
        }

        // MARK: Go
        CommandMenu("Go") {
            Button("Back") { workspace?.focusedPane.activeTab.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { workspace?.focusedPane.activeTab.goForward() }
                .keyboardShortcut("]")
            Button("Enclosing Folder") { workspace?.focusedPane.activeTab.goUp() }
                .keyboardShortcut(.upArrow)
            Divider()
            Button("Computer") { go(URL(fileURLWithPath: "/")) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Home") { go(FileManager.default.homeDirectoryForCurrentUser) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Desktop") { go(Workspace.folder(.desktopDirectory)) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Documents") { go(Workspace.folder(.documentDirectory)) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Downloads") { go(Workspace.folder(.downloadsDirectory)) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("iCloud Drive") { go(Workspace.iCloudDrive) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Applications") { go(URL(fileURLWithPath: "/Applications")) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Utilities") { go(URL(fileURLWithPath: "/Applications/Utilities")) }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Divider()
            Button("Go to Folder…") { workspace?.showGoToFolder = true }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Connect to Server…") { workspace?.showConnectToServer = true }
                .keyboardShortcut("k")
            Divider()
            Button("Command Palette…") { workspace?.showPalette = true }
                .keyboardShortcut("k", modifiers: [.command, .option])
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
