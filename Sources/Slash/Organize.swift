import SwiftUI
import AppKit

// MARK: - New folder from template

struct TemplateNameSheet: View {
    @Environment(AppStore.self) private var store
    let workspace: Workspace
    let template: FolderTemplate

    var body: some View {
        PromptSheet(title: "New “\(template.name)”", placeholder: "Folder name (e.g. Rossi Marco)", action: "Create") { name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            do {
                let folder = try store.createFromTemplate(template, named: trimmed, in: workspace.currentFolder)
                FileUndo.shared.record("New Folder", [.created(folder)])
                workspace.focusedPane.selection = [folder]
                return true
            } catch {
                NSAlert(error: error).runModal()
                return true
            }
        }
    }
}

// MARK: - Batch rename

struct BatchRenameSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace

    @State private var urls: [URL] = []
    @State private var usePattern = true
    @State private var pattern = "{date}_{name}"
    @State private var start = 1
    @State private var find = ""
    @State private var replace = ""

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func newName(_ index: Int, _ url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var result: String
        if usePattern {
            let modified = FileItem.load(url).modified ?? Date()
            result = pattern
                .replacingOccurrences(of: "{name}", with: base)
                .replacingOccurrences(of: "{n}", with: String(format: "%02d", start + index))
                .replacingOccurrences(of: "{date}", with: Self.dayFormat.string(from: modified))
                .replacingOccurrences(of: "{today}", with: Self.dayFormat.string(from: Date()))
                .replacingOccurrences(of: "{folder}", with: url.deletingLastPathComponent().lastPathComponent)
        } else {
            result = find.isEmpty ? base : base.replacingOccurrences(of: find, with: replace)
        }
        result = result.replacingOccurrences(of: "/", with: "-")
        return ext.isEmpty ? result : result + "." + ext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(urls.count) Items").font(.headline)
            Picker("", selection: $usePattern) {
                Text("Pattern").tag(true)
                Text("Replace Text").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if usePattern {
                TextField("Pattern", text: $pattern).textFieldStyle(.roundedBorder)
                Text("{name} original name · {n} number · {date} date modified · {today} today · {folder} folder name")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Start numbers at \(start)", value: $start, in: 0...9999)
            } else {
                TextField("Find", text: $find).textFieldStyle(.roundedBorder)
                TextField("Replace with", text: $replace).textFieldStyle(.roundedBorder)
            }

            List(Array(urls.enumerated()), id: \.element) { i, url in
                HStack {
                    Text(url.lastPathComponent).lineLimit(1).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Text(newName(i, url)).lineLimit(1)
                }
                .font(.callout)
            }
            .frame(height: 220)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { urls = workspace.selectedURLs }
    }

    private func apply() {
        let targets = urls.enumerated().map { (src: $0.element, dest: $0.element.deletingLastPathComponent().appendingPathComponent(newName($0.offset, $0.element))) }
        let newPaths = targets.map(\.dest.path)
        if Set(newPaths).count != newPaths.count {
            let a = NSAlert(); a.messageText = "Some items would get the same name. Add {n} to the pattern."; a.runModal(); return
        }
        var ops: [UndoOp] = []
        var renamed: Set<URL> = []
        for t in targets where t.src != t.dest {
            if FileManager.default.fileExists(atPath: t.dest.path) {
                let a = NSAlert(); a.messageText = "“\(t.dest.lastPathComponent)” already exists. It was skipped."; a.runModal(); continue
            }
            do {
                try FileManager.default.moveItem(at: t.src, to: t.dest)
                store.moveMetadata(from: t.src.path, to: t.dest.path)
                ops.append(.moved(from: t.src, to: t.dest))
                renamed.insert(t.dest)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        FileUndo.shared.record("Rename", ops)
        workspace.focusedPane.selection = renamed
        dismiss()
    }
}

// MARK: - Smart folders

struct SmartFolderEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var smart: SmartFolder

    var body: some View {
        let prop = store.state.properties.first { $0.id == smart.propertyID }
        Form {
            TextField("Name", text: $smart.name)
            Picker("Property", selection: Binding(get: { smart.propertyID }, set: { smart.propertyID = $0; smart.optionID = nil })) {
                Text("Any").tag(String?.none)
                ForEach(store.state.properties) { Text($0.name).tag(String?.some($0.id)) }
            }
            if let prop {
                Picker("Value", selection: $smart.optionID) {
                    Text("Choose…").tag(String?.none)
                    ForEach(prop.options) { Text($0.name).tag(String?.some($0.id)) }
                }
            }
            TextField("Name contains", text: Binding(get: { smart.nameContains ?? "" }, set: { smart.nameContains = $0.isEmpty ? nil : $0 }))
            Toggle("Only recently modified", isOn: Binding(
                get: { smart.modifiedWithinDays != nil },
                set: { smart.modifiedWithinDays = $0 ? 30 : nil }
            ))
            if let days = smart.modifiedWithinDays {
                Stepper("Within \(days) days", value: Binding(get: { days }, set: { smart.modifiedWithinDays = $0 }), in: 1...365)
            }
            Text("Searches all pinned folders of the current Space.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var list = store.smartFolders
                    if smart.spaceID == nil { smart.spaceID = store.currentSpace?.id }
                    if let i = list.firstIndex(where: { $0.id == smart.id }) { list[i] = smart } else { list.append(smart) }
                    store.smartFolders = list
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(smart.name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

/// One smart folder in the sidebar; results load when expanded.
struct SmartFolderRow: View {
    @Environment(AppStore.self) private var store
    let smart: SmartFolder
    let workspace: Workspace
    let edit: () -> Void

    @State private var expanded = false
    @State private var results: [FileItem] = []
    @State private var loading = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if loading && results.isEmpty {
                ProgressView().controlSize(.small)
            } else if results.isEmpty {
                Text("No items").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(results.prefix(100)) { item in
                SidebarItemButton(item: item, workspace: workspace)
            }
        } label: {
            Label(smart.name, systemImage: "folder.badge.gearshape")
                .contextMenu {
                    Button("Refresh") { Task { await load() } }
                    Button("Edit…", action: edit)
                    Button("Delete", role: .destructive) { store.smartFolders.removeAll { $0.id == smart.id } }
                }
        }
        .task(id: expanded) { if expanded { await load() } }
    }

    private func load() async {
        loading = true
        results = await store.results(for: smart)
        loading = false
    }
}

/// A file or folder shown in the sidebar: click opens it, right-click reveals it.
struct SidebarItemButton: View {
    @Environment(AppStore.self) private var store
    let item: FileItem
    let workspace: Workspace

    var body: some View {
        Button {
            if item.isDirectory { workspace.open(item.url) } else { NSWorkspace.shared.open(item.url) }
        } label: {
            Label {
                Text(store.displayName(for: item.url)).lineLimit(1)
            } icon: {
                FolderIconView(url: item.url, isDirectory: item.isDirectory, size: 15)
            }
        }
        .buttonStyle(.plain)
        .draggable(item.url)
        .contextMenu {
            Button("Show in Folder") {
                workspace.open(item.url.deletingLastPathComponent())
                workspace.focusedPane.selection = [item.url]
            }
            Button("Open") { NSWorkspace.shared.open(item.url) }
        }
    }
}

// MARK: - Space overview

struct SpaceOverview: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @State private var newLink = ""

    var body: some View {
        let space = store.currentSpace
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: space?.symbol ?? "square.stack").font(.title)
                TextField("Space name", text: Binding(
                    get: { store.currentSpace?.name ?? "" },
                    set: { v in store.updateCurrentSpace { $0.name = v } }
                ))
                .font(.title2.bold())
                .textFieldStyle(.plain)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Folders") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                            ForEach(space?.pinnedPaths ?? [], id: \.self) { path in
                                let url = URL(fileURLWithPath: path)
                                Button {
                                    workspace.open(url)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 6) {
                                        FolderIconView(url: url, isDirectory: true, size: 44)
                                        Text(store.displayName(for: url)).font(.callout).lineLimit(2).multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 90)
                                    .padding(8)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !store.smartFolders.filter({ $0.spaceID == space?.id }).isEmpty {
                        section("Smart Folders") {
                            ForEach(store.smartFolders.filter { $0.spaceID == space?.id }) { s in
                                Label(s.name, systemImage: "folder.badge.gearshape")
                            }
                        }
                    }

                    section("Links") {
                        ForEach(space?.links ?? [], id: \.self) { link in
                            HStack {
                                Button(link) { if let u = URL(string: link) { NSWorkspace.shared.open(u) } }
                                    .buttonStyle(.link)
                                Spacer()
                                Button { store.updateCurrentSpace { $0.links.removeAll { $0 == link } } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                        HStack {
                            TextField("https://… (Drive, website, shared folder)", text: $newLink)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addLink)
                            Button("Add", action: addLink).disabled(newLink.isEmpty)
                        }
                    }

                    section("Privacy") {
                        Toggle("Private Space: unlock with Touch ID and hide from screen sharing", isOn: Binding(
                            get: { store.currentSpace?.isPrivate == true },
                            set: { v in
                                store.updateCurrentSpace { $0.isPrivate = v ? true : nil }
                                PrivacyGuard.applyWindowSharing(isPrivate: v)
                            }
                        ))
                        Text("Its folders are closed when the Mac locks or sleeps, and are not reopened at launch.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    section("Notes") {
                        TextEditor(text: Binding(
                            get: { store.currentSpace?.notes ?? "" },
                            set: { v in store.updateCurrentSpace { $0.notes = v.isEmpty ? nil : v } }
                        ))
                        .font(.body)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
    }

    private func addLink() {
        var link = newLink.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty else { return }
        if !link.contains("://") { link = "https://" + link }
        store.updateCurrentSpace { if !$0.links.contains(link) { $0.links.append(link) } }
        newLink = ""
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Related items menu (in each pane's ⋯ menu)

struct RelatedMenu: View {
    @Environment(AppStore.self) private var store
    let folder: URL
    let tab: FolderTab
    let addWebLink: () -> Void

    var body: some View {
        let rel = store.relations(for: folder.path)
        Menu("Related") {
            ForEach(rel.relatedPaths, id: \.self) { path in
                Button { tab.navigate(to: URL(fileURLWithPath: path)) } label: {
                    Label(store.displayName(for: URL(fileURLWithPath: path)), systemImage: "folder")
                }
            }
            ForEach(rel.urls, id: \.self) { link in
                Button { if let u = URL(string: link) { NSWorkspace.shared.open(u) } } label: {
                    Label(link, systemImage: "link")
                }
            }
            if !rel.relatedPaths.isEmpty || !rel.urls.isEmpty { Divider() }
            Button("Link a Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = true
                panel.prompt = "Link"
                if panel.runModal() == .OK {
                    for url in panel.urls { store.relate(folder.path, url.path) }
                }
            }
            Button("Add Web Link…", action: addWebLink)
            if !rel.relatedPaths.isEmpty || !rel.urls.isEmpty {
                Menu("Remove") {
                    ForEach(rel.relatedPaths, id: \.self) { path in
                        Button(store.displayName(for: URL(fileURLWithPath: path))) { store.unrelate(folder.path, path) }
                    }
                    ForEach(rel.urls, id: \.self) { link in
                        Button(link) { store.removeLink(link, from: folder.path) }
                    }
                }
            }
        }
    }
}

// MARK: - Template editor (Settings)

struct TemplatesSettings: View {
    @Environment(AppStore.self) private var store
    @State private var selectedID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                List(selection: $selectedID) {
                    ForEach(store.templates) { t in Text(t.name).tag(t.id) }
                }
                .frame(width: 170)
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                    Button { remove() } label: { Image(systemName: "minus") }.disabled(selectedID == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
            }
            if let i = store.templates.firstIndex(where: { $0.id == selectedID }) {
                Form {
                    TextField("Name", text: Binding(get: { store.templates[i].name }, set: { store.templates[i].name = $0 }))
                    Text("Subfolders (one per line, use / for nested folders)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { store.templates[i].subfolders.joined(separator: "\n") },
                        set: { store.templates[i].subfolders = $0.components(separatedBy: "\n") }
                    ))
                    .font(.body.monospaced())
                    .frame(height: 160)
                }
            } else {
                Text("Select a template").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private func add() {
        let t = FolderTemplate(name: "New Template", subfolders: ["Documents", "Notes"])
        store.templates.append(t)
        selectedID = t.id
    }

    private func remove() {
        store.templates.removeAll { $0.id == selectedID }
        selectedID = nil
    }
}
