import SwiftUI
import AppKit

struct PaneView: View {
    @Environment(AppStore.self) private var store
    let workspace: Workspace
    let pane: Pane

    @State private var renamingNickname: URL?
    @State private var nicknameText = ""
    @State private var iconTarget: IdentifiedURL?
    @State private var subfolderResults: [FileItem] = []
    @State private var addingWebLink = false
    @State private var showNote = false
    @State private var reminderTarget: IdentifiedURL?

    private var tab: FolderTab { pane.activeTab }
    private var isFocused: Bool { workspace.focusedPaneID == pane.id }
    private var folderPath: String { tab.url.path }
    private var view: FolderView { store.viewSet(for: folderPath).active }
    private var mode: ViewMode { view.mode ?? .list }

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(workspace: workspace, pane: pane)
            pathBar
            if showNote { FolderNoteBar(path: folderPath) }
            if pane.searchActive { searchBar }
            Divider()
            HStack(spacing: 0) {
                switch mode {
                case .list: listView
                case .icons: iconView
                case .columns: ColumnBrowser(workspace: workspace, pane: pane, menu: { AnyView(menuItems(for: $0)) })
                case .gallery: GalleryView(items: groups.flatMap(\.items), pane: pane, open: open, menu: { AnyView(menuItems(for: $0)) })
                }
                if workspace.showPreview {
                    Divider()
                    PreviewPanel(url: pane.selection.count == 1 ? pane.selection.first : nil)
                        .frame(width: 300)
                }
            }
        }
        .overlay(alignment: .top) {
            if isFocused && workspace.panes.count > 1 {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { workspace.focusedPaneID = pane.id })
        .onChange(of: tab.url) {
            pane.columnPath = []
            pane.searchActive = false
            pane.searchText = ""
        }
        .task(id: "\(pane.searchSubfolders)|\(pane.searchText)|\(folderPath)") { await searchSubfolders() }
        .alert("Nickname", isPresented: Binding(get: { renamingNickname != nil }, set: { if !$0 { renamingNickname = nil } })) {
            TextField("Nickname (leave empty to remove)", text: $nicknameText)
            Button("Save") {
                if let u = renamingNickname { store.setNickname(nicknameText, for: u.path) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown in Slash only. The real file name is not changed.")
        }
        .sheet(item: $iconTarget) { target in
            IconPickerView(path: target.url.path).environment(store)
        }
        .sheet(item: $reminderTarget) { target in
            ReminderSheet(url: target.url).environment(store)
        }
        .sheet(isPresented: $addingWebLink) {
            PromptSheet(title: "Add Web Link", placeholder: "https://…", action: "Add") { text in
                var link = text.trimmingCharacters(in: .whitespaces)
                guard !link.isEmpty else { return false }
                if !link.contains("://") { link = "https://" + link }
                store.addLink(link, to: folderPath)
                return true
            }
        }
        .popover(isPresented: Binding(get: { pane.showViewOptions }, set: { pane.showViewOptions = $0 })) {
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
            Picker("View", selection: Binding(get: { mode }, set: { m in focus(); workspace.setViewMode(m) })) {
                ForEach(ViewMode.allCases) { Image(systemName: $0.symbol).help($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            viewSwitcher
            Button { pane.showViewOptions = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                .help("View options (⌘J)")
            Button { pane.searchActive.toggle() } label: { Image(systemName: "magnifyingglass") }
                .help("Search (⌘F)")
            Button { showNote.toggle() } label: {
                Image(systemName: store.note(for: folderPath).isEmpty ? "note.text" : "note.text.badge.plus")
                    .foregroundStyle(store.note(for: folderPath).isEmpty ? Color.primary : Color.orange)
            }
            .help("Folder note")
            Menu {
                Button("Pin to Sidebar") { store.pin(folderPath) }
                Menu("New Folder from Template") {
                    ForEach(store.templates) { t in
                        Button(t.name) { focus(); workspace.pendingTemplate = t }
                    }
                }
                RelatedMenu(folder: tab.url, tab: tab) { addingWebLink = true }
                Button("Set Folder Icon…") { iconTarget = IdentifiedURL(url: tab.url) }
                Button("New Folder") { focus(); workspace.newFolder() }
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

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search in “\(store.displayName(for: tab.url))”", text: Binding(get: { pane.searchText }, set: { pane.searchText = $0 }))
                .textFieldStyle(.plain)
                .onKeyPress(.escape) { pane.searchActive = false; pane.searchText = ""; return .handled }
            Picker("", selection: Binding(get: { pane.searchSubfolders }, set: { pane.searchSubfolders = $0 })) {
                Text("This folder").tag(false)
                Text("Subfolders & contents").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button { pane.searchActive = false; pane.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5))
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
                pane.showViewOptions = true
            }
        } label: { Text(set.active.title).font(.callout) }
            .menuStyle(.borderlessButton)
            .fixedSize()
    }

    // MARK: Data

    private var visibleItems: [FileItem] {
        let q = pane.searchText.trimmingCharacters(in: .whitespaces)
        guard pane.searchActive, !q.isEmpty else { return tab.items }
        if pane.searchSubfolders { return subfolderResults }
        return tab.items.filter { store.displayName(for: $0.url).localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var groups: [FileGroup] {
        FileArranger.arrange(visibleItems, view: view, store: store)
    }

    private func searchSubfolders() async {
        let q = pane.searchText.trimmingCharacters(in: .whitespaces)
        guard pane.searchActive, pane.searchSubfolders, !q.isEmpty else { subfolderResults = []; return }
        try? await Task.sleep(for: .milliseconds(250)) // debounce typing
        if Task.isCancelled { return }
        let root = tab.url
        subfolderResults = await Task.detached(priority: .userInitiated) {
            var out: [FileItem] = []
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: FileItem.resourceKeys,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return out }
            for case let url as URL in e {
                if url.lastPathComponent.localizedCaseInsensitiveContains(q) { out.append(FileItem.load(url)) }
                if out.count >= 2000 { break }
            }
            return out
        }.value
        // Spotlight adds files whose *contents* match (PDF, Word, text…), where the folder is indexed.
        let byContent = await SpotlightSearch.find(q, in: root)
        if Task.isCancelled { return }
        var seen = Set(subfolderResults.map(\.url.standardizedFileURL))
        let extra = byContent.filter { seen.insert($0.standardizedFileURL).inserted }
        if !extra.isEmpty {
            subfolderResults += await Task.detached { extra.map(FileItem.load) }.value
        }
    }

    private func focus() { workspace.focusedPaneID = pane.id }

    // MARK: List view

    private var listView: some View {
        let selection = Binding(get: { pane.selection }, set: { pane.selection = $0; focus() })

        return VStack(spacing: 0) {
            ListHeader(view: view) { key in focus(); workspace.sort(by: key) }
            Divider()
            List(selection: selection) {
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
            .onKeyPress(.return) {
                focus()
                workspace.beginRename()
                return .handled
            }
        }
    }

    @ViewBuilder
    private func rows(_ items: [FileItem]) -> some View {
        ForEach(items) { item in
            FileRow(item: item, workspace: workspace, pane: pane)
                .tag(item.url)
                .draggable(item.url)
        }
    }

    // MARK: Icon view

    private var iconView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    if let title = group.title {
                        Text(title).font(.headline).padding(.horizontal, 4)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 8)], spacing: 12) {
                        ForEach(group.items) { item in
                            IconCell(item: item, workspace: workspace, pane: pane)
                                .onTapGesture(count: 2) { open(item.url) }
                                .onTapGesture { select(item.url) }
                                .contextMenu { menuItems(for: pane.selection.contains(item.url) ? Array(pane.selection) : [item.url]) }
                                .draggable(item.url)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { pane.selection = []; focus() }
        .contextMenu { menuItems(for: []) }
        .dropDestination(for: URL.self) { urls, _ in
            FileOps.move(urls, to: tab.url, copy: NSEvent.modifierFlags.contains(.option), store: store)
            return true
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            if let first = pane.selection.first { QuickLook.show(first) }
            return .handled
        }
        .onKeyPress(.return) { focus(); workspace.beginRename(); return .handled }
    }

    /// Click = select, ⌘-click = add/remove, ⇧-click = add.
    private func select(_ url: URL) {
        focus()
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            if pane.selection.contains(url) && flags.contains(.command) { pane.selection.remove(url) } else { pane.selection.insert(url) }
        } else {
            pane.selection = [url]
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
            Button("New Folder") { focus(); workspace.newFolder() }
            Button("Paste") { focus(); workspace.paste(move: false) }
            Button("Pin This Folder") { store.pin(folderPath) }
            Button("Get Info") { focus(); pane.selection = []; workspace.getInfo() }
        } else {
            Button("Open") { urls.forEach(open) }
            if urls.count == 1, FileItem.load(urls[0]).isDirectory {
                Button("Open in New Tab") { pane.openTab(urls[0], store: store) }
                if let other = workspace.otherPane {
                    Button("Open in Other Pane") { other.activeTab.navigate(to: urls[0]) }
                }
                Button("Pin to Sidebar") { store.pin(urls[0].path) }
                Button("Set Icon…") { iconTarget = IdentifiedURL(url: urls[0]) }
            }
            OpenWithMenu(urls: urls)
            Button("Quick Look") { QuickLook.show(urls[0]) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            ShareMenu(urls: urls)
            ServicesMenu(urls: urls)
            CloudMenu(urls: urls)
            Button("Compress") { Archive.compress(urls) }
            if urls.count == 1 {
                Button("Remind Me…") { reminderTarget = IdentifiedURL(url: urls[0]) }
            }
            Divider()
            Button("Get Info") { focus(); pane.selection = Set(urls); workspace.getInfo() }
            if urls.count == 1 {
                Button("Rename") { focus(); pane.selection = Set(urls); workspace.beginRename() }
            } else {
                Button("Rename \(urls.count) Items…") { focus(); pane.selection = Set(urls); workspace.showBatchRename = true }
            }
            Button("Duplicate") { focus(); pane.selection = Set(urls); workspace.duplicateSelection() }
            Button("Make Alias") { focus(); pane.selection = Set(urls); workspace.makeAlias() }
            Button("Copy") { focus(); pane.selection = Set(urls); workspace.copySelection() }
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
                    Divider()
                    Button("Create PDF") { PDFTools.fromImages(urls.filter(ImageOps.isImage)) }
                }
            }
            if urls.contains(where: PDFTools.isPDF) {
                Menu("PDF") {
                    if urls.filter(PDFTools.isPDF).count > 1 {
                        Button("Combine into One PDF") { PDFTools.combine(urls.filter(PDFTools.isPDF)) }
                    }
                    Button("Split into Pages") { urls.filter(PDFTools.isPDF).forEach(PDFTools.split) }
                }
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            }
            Button("Move to Trash", role: .destructive) {
                focus(); pane.selection = Set(urls); workspace.trashSelection()
            }
            Button("Delete Immediately…", role: .destructive) { Deletion.deleteImmediately(urls) }
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

    private func openInTerminal(_ url: URL) {
        guard let term = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - List header (click to sort, like Finder)

struct ListHeader: View {
    let view: FolderView
    let sort: (SortKey) -> Void

    var body: some View {
        HStack(spacing: 8) {
            header("Name", .name).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 34)
            header("Date Modified", .modified).frame(width: 150, alignment: .trailing)
            header("Size", .size).frame(width: 70, alignment: .trailing)
            header("Kind", .kind).frame(width: 130, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func header(_ title: String, _ key: SortKey) -> some View {
        Button { sort(key) } label: {
            HStack(spacing: 3) {
                Text(title).fontWeight(view.sortKey == key ? .semibold : .regular)
                if view.sortKey == key {
                    Image(systemName: view.ascending ? "chevron.up" : "chevron.down").font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline rename

struct RenameField: View {
    let item: FileItem
    let workspace: Workspace
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear {
                text = item.name
                focused = true
            }
            .onSubmit { workspace.rename(item.url, to: text) }
            .onKeyPress(.escape) { workspace.focusedPane.renaming = nil; return .handled }
            .onChange(of: focused) { _, isFocused in
                if !isFocused, workspace.focusedPane.renaming == item.url { workspace.rename(item.url, to: text) }
            }
    }
}

// MARK: - Row

struct FileRow: View {
    @Environment(AppStore.self) private var store
    let item: FileItem
    let workspace: Workspace
    let pane: Pane

    var body: some View {
        HStack(spacing: 8) {
            FolderIconView(url: item.url, isDirectory: item.isDirectory, size: 18)
            if pane.renaming == item.url {
                RenameField(item: item, workspace: workspace)
            } else {
                Text(store.displayName(for: item.url))
                    .lineLimit(1)
                if store.state.nicknames[item.path] != nil {
                    Text(item.name).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            ForEach(item.tags, id: \.self) { tag in
                Circle().fill(FinderTagColor.color(for: tag)).frame(width: 8, height: 8).help(tag)
            }
            if item.isCloudOnly {
                Image(systemName: "icloud").font(.caption).foregroundStyle(.secondary).help("Only in the cloud")
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
            Group {
                if let m = item.modified {
                    Text(m, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                } else {
                    Text("—")
                }
            }
            .font(.callout).foregroundStyle(.secondary)
            .frame(width: 150, alignment: .trailing)
            Text(item.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: item.size ?? 0, countStyle: .file))
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(item.kind)
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: 130, alignment: .leading)
        }
        .opacity(item.isHidden ? 0.5 : 1)
    }
}

/// Finder's standard tag colors (custom tags show gray).
enum FinderTagColor {
    static func color(for tag: String) -> Color {
        switch tag.lowercased() {
        case "red", "rosso": .red
        case "orange", "arancione": .orange
        case "yellow", "giallo": .yellow
        case "green", "verde": .green
        case "blue", "blu": .blue
        case "purple", "viola": .purple
        default: .gray
        }
    }
}

// MARK: - Icon cell

struct IconCell: View {
    @Environment(AppStore.self) private var store
    let item: FileItem
    let workspace: Workspace
    let pane: Pane

    var body: some View {
        let selected = pane.selection.contains(item.url)
        VStack(spacing: 4) {
            FolderIconView(url: item.url, isDirectory: item.isDirectory, size: 56)
                .padding(4)
                .background(selected ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            if pane.renaming == item.url {
                RenameField(item: item, workspace: workspace)
            } else {
                Text(store.displayName(for: item.url))
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            HStack(spacing: 2) {
                ForEach(item.tags, id: \.self) { Circle().fill(FinderTagColor.color(for: $0)).frame(width: 6, height: 6) }
            }
        }
        .frame(width: 100)
        .opacity(item.isHidden ? 0.5 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Column view

struct ColumnBrowser: View {
    @Environment(AppStore.self) private var store
    let workspace: Workspace
    let pane: Pane
    let menu: ([URL]) -> AnyView

    private var columns: [URL] { [pane.activeTab.url] + pane.columnPath }

    /// The file selected in the last column (shown in the preview column).
    private var selectedFile: URL? {
        guard pane.selection.count == 1, let url = pane.selection.first, !pane.columnPath.contains(url) else { return nil }
        return url
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.element) { index, folder in
                        ColumnList(folder: folder, index: index, workspace: workspace, pane: pane, menu: menu)
                            .frame(width: 230)
                            .id(index)
                        Divider()
                    }
                    if let file = selectedFile {
                        ColumnPreview(item: FileItem.load(file))
                            .frame(width: 260)
                            .id("preview")
                    }
                }
            }
            .onChange(of: pane.columnPath) {
                withAnimation { proxy.scrollTo(selectedFile == nil ? AnyHashable(columns.count - 1) : AnyHashable("preview"), anchor: .trailing) }
            }
        }
    }
}

struct ColumnList: View {
    @Environment(AppStore.self) private var store
    let folder: URL
    let index: Int
    let workspace: Workspace
    let pane: Pane
    let menu: ([URL]) -> AnyView

    @State private var items: [FileItem] = []
    @State private var watcher: DirectoryWatcher?

    private var selectedChild: URL? {
        if index < pane.columnPath.count { return pane.columnPath[index] }
        if index == pane.columnPath.count, pane.selection.count == 1, let s = pane.selection.first,
           s.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL { return s }
        return nil
    }

    var body: some View {
        let view = store.viewSet(for: pane.activeTab.url.path).active
        var flat = view
        flat.groupKey = nil
        flat.groupByPropertyID = nil
        let sorted = FileArranger.arrange(items, view: flat, store: store).flatMap(\.items)

        return List(selection: Binding<URL?>(
            get: { selectedChild },
            set: { url in
                workspace.focusedPaneID = pane.id
                guard let url else { return }
                let base = Array(pane.columnPath.prefix(index))
                if FileItem.load(url).isDirectory {
                    pane.columnPath = base + [url]
                } else {
                    pane.columnPath = base
                }
                pane.selection = [url]
            }
        )) {
            ForEach(sorted) { item in
                HStack(spacing: 6) {
                    FolderIconView(url: item.url, isDirectory: item.isDirectory, size: 16)
                    if pane.renaming == item.url {
                        RenameField(item: item, workspace: workspace)
                    } else {
                        Text(store.displayName(for: item.url)).lineLimit(1)
                    }
                    Spacer()
                    if item.isDirectory { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                }
                .opacity(item.isHidden ? 0.5 : 1)
                .tag(item.url)
                .draggable(item.url)
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: URL.self) { urls in
            menu(Array(urls))
        } primaryAction: { urls in
            for url in urls {
                if FileItem.load(url).isDirectory { pane.activeTab.navigate(to: url) } else { NSWorkspace.shared.open(url) }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            FileOps.move(urls, to: folder, copy: NSEvent.modifierFlags.contains(.option), store: store)
            return true
        }
        .onKeyPress(.space) {
            if let first = pane.selection.first { QuickLook.show(first) }
            return .handled
        }
        .onKeyPress(.return) { workspace.focusedPaneID = pane.id; workspace.beginRename(); return .handled }
        .onAppear(perform: load)
        .onChange(of: folder) { load() }
    }

    private func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: FileItem.resourceKeys)) ?? []
        items = urls.map(FileItem.load)
        watcher = DirectoryWatcher(url: folder) {
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: FileItem.resourceKeys)) ?? []
            items = urls.map(FileItem.load)
        }
    }
}

struct ColumnPreview: View {
    @Environment(AppStore.self) private var store
    let item: FileItem

    var body: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 20)
            FolderIconView(url: item.url, isDirectory: item.isDirectory, size: 128)
            Text(store.displayName(for: item.url)).font(.headline).multilineTextAlignment(.center)
            Text(item.kind + (item.size.map { " · " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""))
                .font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, verticalSpacing: 4) {
                if let d = item.created { info("Created", d) }
                if let d = item.modified { info("Modified", d) }
                if let d = FileItem.lastOpened(item.url) { info("Last opened", d) }
            }
            .font(.caption)
            Spacer()
        }
        .padding()
    }

    private func info(_ label: String, _ date: Date) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
        }
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
                            if let icon = store.icon(for: tab.url.path) {
                                Image(systemName: icon.symbol).font(.caption).foregroundStyle(icon.color.color)
                            } else {
                                Image(systemName: "folder.fill").font(.caption).foregroundStyle(.secondary)
                            }
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

        // "Date Last Opened" comes from Spotlight: read it once per item, only when needed.
        var lastOpened: [URL: Date] = [:]
        if view.sortKey == .lastOpened || view.groupKey == .lastOpened {
            for item in list { lastOpened[item.url] = FileItem.lastOpened(item.url) }
        }

        list.sort { a, b in
            if view.foldersFirst && a.isDirectory != b.isDirectory { return a.isDirectory }
            let r: ComparisonResult
            switch view.sortKey {
            case .name: r = store.displayName(for: a.url).localizedStandardCompare(store.displayName(for: b.url))
            case .kind: r = a.kind.localizedStandardCompare(b.kind)
            case .tags: r = (a.tags.first ?? "\u{FFFF}").localizedStandardCompare(b.tags.first ?? "\u{FFFF}")
            case .modified: r = compare(a.modified, b.modified)
            case .created: r = compare(a.created, b.created)
            case .added: r = compare(a.added, b.added)
            case .lastOpened: r = compare(lastOpened[a.url], lastOpened[b.url])
            case .size: r = compare(a.size ?? -1, b.size ?? -1)
            }
            if r == .orderedSame {
                return store.displayName(for: a.url).localizedStandardCompare(store.displayName(for: b.url)) == .orderedAscending
            }
            return view.ascending ? r == .orderedAscending : r == .orderedDescending
        }

        if let key = view.groupKey {
            return group(list, by: key, lastOpened: lastOpened)
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

    private static func compare<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult {
        switch (a, b) {
        case let (x?, y?): x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (nil, _?): .orderedAscending
        case (_?, nil): .orderedDescending
        default: .orderedSame
        }
    }

    /// Buckets like Finder's "Use Groups". Items keep their sort order inside each group.
    private static func group(_ list: [FileItem], by key: GroupKey, lastOpened: [URL: Date]) -> [FileGroup] {
        var buckets: [String: (order: Int, items: [FileItem])] = [:]
        for item in list {
            let bucket: (Int, String)
            switch key {
            case .kind: bucket = (0, item.kind)
            case .tags: bucket = item.tags.first.map { (0, $0) } ?? (1, "No Tags")
            case .size: bucket = sizeBucket(item)
            case .modified: bucket = dateBucket(item.modified)
            case .created: bucket = dateBucket(item.created)
            case .added: bucket = dateBucket(item.added)
            case .lastOpened: bucket = dateBucket(lastOpened[item.url])
            }
            buckets[bucket.1, default: (bucket.0, [])].items.append(item)
        }
        return buckets
            .sorted { $0.value.order != $1.value.order ? $0.value.order < $1.value.order : $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { FileGroup(id: $0.key, title: $0.key, items: $0.value.items) }
    }

    private static func dateBucket(_ date: Date?) -> (Int, String) {
        guard let d = date else { return (99_999, "Unknown") }
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(d) { return (0, "Today") }
        if cal.isDateInYesterday(d) { return (1, "Yesterday") }
        let days = cal.dateComponents([.day], from: d, to: now).day ?? 0
        if days < 7 { return (2, "Previous 7 Days") }
        if days < 30 { return (3, "Previous 30 Days") }
        let year = cal.component(.year, from: d)
        if year == cal.component(.year, from: now) {
            return (100 - cal.component(.month, from: d), d.formatted(.dateTime.month(.wide)))
        }
        return (10_000 - year, String(year))
    }

    private static func sizeBucket(_ item: FileItem) -> (Int, String) {
        if item.isDirectory { return (0, "Folders") }
        let s = item.size ?? 0
        let mb: Int64 = 1_000_000
        switch s {
        case 0: return (1, "Zero KB")
        case ..<(100 * 1000): return (2, "Less than 100 KB")
        case ..<mb: return (3, "100 KB to 1 MB")
        case ..<(100 * mb): return (4, "1 MB to 100 MB")
        case ..<(1000 * mb): return (5, "100 MB to 1 GB")
        default: return (6, "More than 1 GB")
        }
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
        // One picker for both Finder criteria ("k:kind") and Slash properties ("p:<id>")
        let groupSelection = Binding<String>(
            get: {
                if let k = binding.wrappedValue.groupKey { return "k:" + k.rawValue }
                if let p = binding.wrappedValue.groupByPropertyID { return "p:" + p }
                return "none"
            },
            set: { value in
                var v = binding.wrappedValue
                v.groupKey = value.hasPrefix("k:") ? GroupKey(rawValue: String(value.dropFirst(2))) : nil
                v.groupByPropertyID = value.hasPrefix("p:") ? String(value.dropFirst(2)) : nil
                binding.wrappedValue = v
            }
        )
        Form {
            TextField("View name", text: binding.title)
            Picker("View as", selection: Binding(get: { binding.wrappedValue.mode ?? .list }, set: { binding.wrappedValue.mode = $0 })) {
                ForEach(ViewMode.allCases) { Text($0.label).tag($0) }
            }
            Picker("Sort by", selection: binding.sortKey) {
                ForEach(SortKey.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Ascending", isOn: binding.ascending)
            Toggle("Folders first", isOn: binding.foldersFirst)
            Toggle("Show hidden files", isOn: binding.showHidden)
            Picker("Group by", selection: groupSelection) {
                Text("None").tag("none")
                Section("Finder") {
                    ForEach(GroupKey.allCases) { Text($0.label).tag("k:" + $0.rawValue) }
                }
                Section("Properties") {
                    ForEach(store.state.properties) { Text($0.name).tag("p:" + $0.id) }
                }
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
        .frame(width: 340)
    }
}
