import SwiftUI
import AppKit

struct PaneView: View {
    @Environment(AppStore.self) private var store
    let workspace: Workspace
    let pane: Pane

    @State private var renamingNickname: URL?
    @State private var nicknameText = ""
    @State private var showViewEditor = false

    private var tab: FolderTab { pane.activeTab }
    private var isFocused: Bool { workspace.focusedPaneID == pane.id }
    private var folderPath: String { tab.url.path }

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(workspace: workspace, pane: pane)
            pathBar
            Divider()
            fileList
        }
        .overlay(alignment: .top) {
            if isFocused && workspace.panes.count > 1 {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { workspace.focusedPaneID = pane.id })
        .alert("Nickname", isPresented: Binding(get: { renamingNickname != nil }, set: { if !$0 { renamingNickname = nil } })) {
            TextField("Nickname (leave empty to remove)", text: $nicknameText)
            Button("Save") {
                if let u = renamingNickname { store.setNickname(nicknameText, for: u.path) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown in Slash only. The real file name is not changed.")
        }
        .popover(isPresented: $showViewEditor) {
            FolderViewEditor(folderPath: folderPath)
                .environment(store)
        }
    }

    // MARK: Path bar

    private var pathBar: some View {
        HStack(spacing: 6) {
            Button { tab.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!tab.canGoBack)
            Button { tab.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!tab.canGoForward)
            Button { tab.goUp() } label: { Image(systemName: "arrow.up") }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(breadcrumbs, id: \.self) { url in
                        Button(store.displayName(for: url)) { tab.navigate(to: url) }
                            .buttonStyle(.plain)
                            .foregroundStyle(url == tab.url ? .primary : .secondary)
                        if url != tab.url { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                    }
                }
            }

            Spacer()
            viewSwitcher
            Button { showViewEditor = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                .help("Sort, group & filter")
            Menu {
                Button("Pin to Sidebar") { store.pin(folderPath) }
                Button("New Folder") { newFolder() }
                Button("Open in Finder") { NSWorkspace.shared.open(tab.url) }
                Button("Open in Terminal") { openInTerminal(tab.url) }
                if workspace.panes.count > 1 {
                    Divider()
                    Button("Close Pane") { workspace.closePane(pane.id) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var breadcrumbs: [URL] {
        var urls: [URL] = []
        var u = tab.url
        while true {
            urls.insert(u, at: 0)
            let parent = u.deletingLastPathComponent()
            if parent.path == u.path || urls.count > 12 { break }
            u = parent
        }
        return urls
    }

    /// Switch between several saved views of the same folder.
    private var viewSwitcher: some View {
        let set = store.viewSet(for: folderPath)
        return Menu {
            ForEach(set.views) { v in
                Button {
                    var s = set; s.activeID = v.id; store.setViewSet(s, for: folderPath)
                } label: {
                    if v.id == set.active.id { Label(v.title, systemImage: "checkmark") } else { Text(v.title) }
                }
            }
            Divider()
            Button("New View") {
                var s = set
                var v = set.active
                v.id = UUID().uuidString
                v.title = "View \(s.views.count + 1)"
                s.views.append(v)
                s.activeID = v.id
                store.setViewSet(s, for: folderPath)
                showViewEditor = true
            }
        } label: { Text(set.active.title).font(.callout) }
            .menuStyle(.borderlessButton)
            .fixedSize()
    }

    // MARK: File list

    private var fileList: some View {
        let view = store.viewSet(for: folderPath).active
        let groups = FileArranger.arrange(tab.items, view: view, store: store)
        let selection = Binding(get: { pane.selection }, set: { pane.selection = $0; workspace.focusedPaneID = pane.id })

        return List(selection: selection) {
            if let error = tab.error {
                Text(error).foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                if let title = group.title {
                    Section(title) { rows(group.items) }
                } else {
                    rows(group.items)
                }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: URL.self) { urls in
            menuItems(for: Array(urls))
        } primaryAction: { urls in
            urls.forEach(open)
        }
        .dropDestination(for: URL.self) { urls, _ in
            FileOps.move(urls, to: tab.url, copy: NSEvent.modifierFlags.contains(.option), store: store)
            return true
        }
        .onKeyPress(.space) {
            if let first = pane.selection.first { QuickLook.show(first) }
            return .handled
        }
    }

    @ViewBuilder
    private func rows(_ items: [FileItem]) -> some View {
        ForEach(items) { item in
            FileRow(item: item)
                .tag(item.url)
                .draggable(item.url)
        }
    }

    // MARK: Actions

    private func open(_ url: URL) {
        if FileItem.load(url).isDirectory {
            if NSEvent.modifierFlags.contains(.command) { pane.openTab(url, store: store) } else { tab.navigate(to: url) }
            pane.selection = []
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private func menuItems(for urls: [URL]) -> some View {
        if urls.isEmpty {
            Button("New Folder") { newFolder() }
            Button("Pin This Folder") { store.pin(folderPath) }
        } else {
            Button("Open") { urls.forEach(open) }
            if urls.count == 1, FileItem.load(urls[0]).isDirectory {
                Button("Open in New Tab") { pane.openTab(urls[0], store: store) }
                if let other = workspace.otherPane {
                    Button("Open in Other Pane") { other.activeTab.navigate(to: urls[0]) }
                }
                Button("Pin to Sidebar") { store.pin(urls[0].path) }
            }
            Button("Quick Look") { QuickLook.show(urls[0]) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            Divider()
            propertyMenus(urls)
            if urls.count == 1 {
                Button("Set Nickname…") {
                    nicknameText = store.state.nicknames[urls[0].path] ?? ""
                    renamingNickname = urls[0]
                }
            }
            if let other = workspace.otherPane {
                Divider()
                Button("Copy to Other Pane") { FileOps.move(urls, to: other.activeTab.url, copy: true, store: store) }
                Button("Move to Other Pane") { FileOps.move(urls, to: other.activeTab.url, copy: false, store: store) }
            }
            if urls.contains(where: ImageOps.isImage) {
                Divider()
                Menu("Image") {
                    Button("Flip Horizontal") { urls.filter(ImageOps.isImage).forEach { ImageOps.flip($0, horizontal: true) } }
                    Button("Flip Vertical") { urls.filter(ImageOps.isImage).forEach { ImageOps.flip($0, horizontal: false) } }
                    Button("Rotate 90°") { urls.filter(ImageOps.isImage).forEach { ImageOps.rotate($0) } }
                    Divider()
                    Button("Convert to PNG") { urls.filter(ImageOps.isImage).forEach { ImageOps.convert($0, to: .png) } }
                    Button("Convert to JPEG") { urls.filter(ImageOps.isImage).forEach { ImageOps.convert($0, to: .jpeg) } }
                }
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            }
            Button("Move to Trash", role: .destructive) {
                for u in urls { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
            }
        }
    }

    @ViewBuilder
    private func propertyMenus(_ urls: [URL]) -> some View {
        ForEach(store.state.properties) { prop in
            Menu(prop.name) {
                ForEach(prop.options) { opt in
                    Button(opt.name) { store.setOption(opt.id, property: prop.id, for: urls.map(\.path)) }
                }
                Divider()
                Button("None") { store.setOption(nil, property: prop.id, for: urls.map(\.path)) }
            }
        }
    }

    private func newFolder() {
        var url = tab.url.appendingPathComponent("New Folder")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = tab.url.appendingPathComponent("New Folder \(n)"); n += 1
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        pane.selection = [url]
    }

    private func openInTerminal(_ url: URL) {
        guard let term = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Row

struct FileRow: View {
    @Environment(AppStore.self) private var store
    let item: FileItem

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 18, height: 18)
            Text(store.displayName(for: item.url))
                .lineLimit(1)
            if store.state.nicknames[item.path] != nil {
                Text(item.name).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            ForEach(store.state.properties) { prop in
                if let opt = store.option(for: item.path, property: prop) {
                    Text(opt.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(opt.color.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(opt.color.color)
                }
            }
            Spacer()
            if let m = item.modified {
                Text(m, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .trailing)
            }
            Text(item.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: item.size ?? 0, countStyle: .file))
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .opacity(item.isHidden ? 0.5 : 1)
    }
}

// MARK: - Tabs

struct TabStrip: View {
    @Environment(AppStore.self) private var store
    let workspace: Workspace
    let pane: Pane

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pane.tabs) { tab in
                        let active = tab.id == pane.activeTabID
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill").font(.caption).foregroundStyle(.secondary)
                            Text(tab.title).lineLimit(1).font(.callout)
                            if pane.tabs.count > 1 {
                                Button { pane.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.caption2) }
                                    .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(active ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            pane.activeTabID = tab.id
                            workspace.focusedPaneID = pane.id
                        }
                        .draggable(tab.url)
                        .dropDestination(for: URL.self) { urls, _ in
                            FileOps.move(urls, to: tab.url, copy: NSEvent.modifierFlags.contains(.option), store: store)
                            return true
                        }
                    }
                }
            }
            Button { pane.openTab(pane.activeTab.url, store: store) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}

// MARK: - Sort / group / filter

struct FileGroup: Identifiable {
    let id: String
    let title: String?
    let items: [FileItem]
}

enum FileArranger {
    static func arrange(_ items: [FileItem], view: FolderView, store: AppStore) -> [FileGroup] {
        var list = items.filter { view.showHidden || !$0.isHidden }

        for (propID, optID) in view.filters {
            list = list.filter { store.state.selections[$0.path]?[propID] == optID }
        }

        list.sort { a, b in
            if view.foldersFirst && a.isDirectory != b.isDirectory { return a.isDirectory }
            let r: Bool
            switch view.sortKey {
            case .name: r = store.displayName(for: a.url).localizedStandardCompare(store.displayName(for: b.url)) == .orderedAscending
            case .modified: r = (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            case .size: r = (a.size ?? 0) < (b.size ?? 0)
            case .kind: r = a.url.pathExtension.localizedStandardCompare(b.url.pathExtension) == .orderedAscending
            }
            return view.ascending ? r : !r
        }

        guard let propID = view.groupByPropertyID,
              let prop = store.state.properties.first(where: { $0.id == propID }) else {
            return [FileGroup(id: "all", title: nil, items: list)]
        }
        var groups: [FileGroup] = prop.options.compactMap { opt in
            let g = list.filter { store.state.selections[$0.path]?[propID] == opt.id }
            return g.isEmpty ? nil : FileGroup(id: opt.id, title: opt.name, items: g)
        }
        let none = list.filter { prop.option(store.state.selections[$0.path]?[propID]) == nil }
        if !none.isEmpty { groups.append(FileGroup(id: "none", title: "No \(prop.name)", items: none)) }
        return groups
    }
}

struct FolderViewEditor: View {
    @Environment(AppStore.self) private var store
    let folderPath: String

    var body: some View {
        let set = store.viewSet(for: folderPath)
        let binding = Binding<FolderView>(
            get: { store.viewSet(for: folderPath).active },
            set: { newValue in var s = store.viewSet(for: folderPath); s.active = newValue; store.setViewSet(s, for: folderPath) }
        )
        Form {
            TextField("View name", text: binding.title)
            Picker("Sort by", selection: binding.sortKey) {
                ForEach(SortKey.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Ascending", isOn: binding.ascending)
            Toggle("Folders first", isOn: binding.foldersFirst)
            Toggle("Show hidden files", isOn: binding.showHidden)
            Picker("Group by", selection: binding.groupByPropertyID) {
                Text("None").tag(String?.none)
                ForEach(store.state.properties) { Text($0.name).tag(String?.some($0.id)) }
            }
            ForEach(store.state.properties) { prop in
                Picker("Filter \(prop.name)", selection: Binding<String?>(
                    get: { binding.wrappedValue.filters[prop.id] },
                    set: { binding.wrappedValue.filters[prop.id] = $0 }
                )) {
                    Text("Any").tag(String?.none)
                    ForEach(prop.options) { Text($0.name).tag(String?.some($0.id)) }
                }
            }
            if set.views.count > 1 {
                Button("Delete This View", role: .destructive) {
                    var s = set
                    let activeID = s.active.id
                    s.views.removeAll { $0.id == activeID }
                    s.activeID = s.views.first?.id
                    store.setViewSet(s, for: folderPath)
                }
            }
        }
        .padding()
        .frame(width: 320)
    }
}
