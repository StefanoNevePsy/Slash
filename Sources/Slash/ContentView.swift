import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppStore.self) private var store
    let workspace: Workspace

    var body: some View {
        NavigationSplitView {
            SidebarView(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(workspace.panes.enumerated()), id: \.element.id) { index, pane in
                        if index > 0 { Divider() }
                        PaneView(workspace: workspace, pane: pane)
                    }
                }
                TransferBar()
            }
        }
        .onChange(of: workspace.session) { workspace.saveSession() }
        .toolbar {
            ToolbarItemGroup {
                Button { workspace.split() } label: { Label("Split", systemImage: "rectangle.split.2x1") }
                    .help("Split pane (⌘\\)")
                Button { workspace.showPalette = true } label: { Label("Go to", systemImage: "magnifyingglass") }
                    .help("Command palette (⌥⌘K)")
            }
        }
        .sheet(isPresented: Binding(get: { workspace.showPalette }, set: { workspace.showPalette = $0 })) {
            CommandPaletteView(workspace: workspace)
                .environment(store)
        }
        .sheet(isPresented: Binding(get: { workspace.showGoToFolder }, set: { workspace.showGoToFolder = $0 })) {
            PromptSheet(title: "Go to Folder", placeholder: "~/Documents or /Volumes/…", action: "Go") { text in
                let path = (text.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
                let url = URL(fileURLWithPath: path)
                if isDir.boolValue {
                    workspace.open(url)
                } else {
                    workspace.open(url.deletingLastPathComponent())
                    workspace.focusedPane.selection = [url]
                }
                return true
            }
        }
        .sheet(isPresented: Binding(get: { workspace.showConnectToServer }, set: { workspace.showConnectToServer = $0 })) {
            PromptSheet(title: "Connect to Server", placeholder: "smb://server/share", action: "Connect") { text in
                guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme != nil else { return false }
                // macOS mounts smb://, afp://, nfs://, ftp:// and WebDAV URLs and asks for credentials itself.
                NSWorkspace.shared.open(url)
                return true
            }
        }
        .navigationTitle(store.currentSpace?.name ?? "Slash")
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    let workspace: Workspace
    @State private var newSpaceName = ""
    @State private var addingSpace = false
    @State private var liveItems: [FileItem] = []
    @State private var iconTarget: IdentifiedURL?

    var body: some View {
        VStack(spacing: 0) {
            spacePicker
            List {
                Section("Pinned") {
                    ForEach(store.currentSpace?.pinnedPaths ?? [], id: \.self) { path in
                        let url = URL(fileURLWithPath: path)
                        Button { workspace.open(url) } label: {
                            Label {
                                Text(store.displayName(for: url))
                            } icon: {
                                FolderIconView(url: url, isDirectory: true, size: 15)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open in New Tab") { workspace.open(url, newTab: true) }
                            Button("Set Icon…") { iconTarget = IdentifiedURL(url: url) }
                            Button("Unpin") { store.unpin(path) }
                        }
                    }
                    .onMove { from, to in store.updateCurrentSpace { $0.pinnedPaths.move(fromOffsets: from, toOffset: to) } }
                    .dropDestination(for: URL.self) { urls, _ in
                        urls.filter { FileItem.load($0).isDirectory }.forEach { store.pin($0.path) }
                        return true
                    }
                }
                Section("Live · Recent changes") {
                    ForEach(liveItems) { item in
                        Button {
                            if item.isDirectory { workspace.open(item.url) } else { NSWorkspace.shared.open(item.url) }
                        } label: {
                            Label(store.displayName(for: item.url), systemImage: item.isDirectory ? "folder" : "doc")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .draggable(item.url)
                    }
                }
                Section("Recent folders") {
                    ForEach(store.state.recentFolders.prefix(6), id: \.self) { path in
                        Button { workspace.open(URL(fileURLWithPath: path)) } label: {
                            Label {
                                Text(store.displayName(for: URL(fileURLWithPath: path)))
                            } icon: {
                                if store.icon(for: path) != nil {
                                    FolderIconView(url: URL(fileURLWithPath: path), isDirectory: true, size: 15)
                                } else {
                                    Image(systemName: "clock")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .task(id: store.currentSpace?.pinnedPaths) { await refreshLive() }
        .sheet(item: $iconTarget) { target in
            IconPickerView(path: target.url.path).environment(store)
        }
        .alert("New Space", isPresented: $addingSpace) {
            TextField("Name", text: $newSpaceName)
            Button("Create") {
                if !newSpaceName.isEmpty { store.addSpace(named: newSpaceName) }
                newSpaceName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var spacePicker: some View {
        HStack {
            Menu {
                ForEach(store.state.spaces) { space in
                    Button(space.name) { store.state.selectedSpaceID = space.id }
                }
                Divider()
                Button("New Space…") { addingSpace = true }
            } label: {
                Label(store.currentSpace?.name ?? "Space", systemImage: store.currentSpace?.symbol ?? "square.stack")
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// "Live Group": files modified in the last 7 days inside the space's pinned folders, refreshed every minute.
    private func refreshLive() async {
        while !Task.isCancelled {
            let roots = (store.currentSpace?.pinnedPaths ?? []).map { URL(fileURLWithPath: $0) }
            let found = await Task.detached(priority: .utility) { LiveScanner.recent(in: roots) }.value
            liveItems = found
            try? await Task.sleep(for: .seconds(60))
        }
    }
}

enum LiveScanner {
    static func recent(in roots: [URL], days: Double = 7, limit: Int = 12) -> [FileItem] {
        let cutoff = Date().addingTimeInterval(-days * 86400)
        var results: [FileItem] = []
        for root in roots {
            guard let e = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var visited = 0
            for case let url as URL in e {
                visited += 1
                if visited > 5000 { break }
                if e.level > 3 { e.skipDescendants(); continue }
                let item = FileItem.load(url)
                if !item.isDirectory, let m = item.modified, m > cutoff { results.append(item) }
            }
        }
        return Array(results.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }.prefix(limit))
    }
}

/// Small text-input sheet used by Go to Folder (⇧⌘G) and Connect to Server (⌘K).
struct PromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    let action: String
    /// Returns false to keep the sheet open (e.g. path not found)
    let submit: (String) -> Bool

    @State private var text = ""
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(run)
            if failed { Text("Not found").font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action, action: run).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focused = true }
    }

    private func run() {
        if submit(text) { dismiss() } else { failed = true }
    }
}

/// Progress of a running copy / move (bottom of the window).
struct TransferBar: View {
    private var transfer: FileTransfer { FileTransfer.shared }

    var body: some View {
        if transfer.isRunning {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Text("\(transfer.title) “\(transfer.currentName)”…").lineLimit(1).font(.callout)
                    ProgressView(value: transfer.fraction).frame(maxWidth: 260)
                    Text("\(Int(transfer.fraction * 100))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Stop") { transfer.cancel() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }
}
