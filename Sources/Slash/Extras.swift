import SwiftUI
import AppKit
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import UserNotifications
import LocalAuthentication

// MARK: - Thumbnails

enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "\(url.path)|\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = rep.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Real preview thumbnail (falls back to the file icon; folders keep their custom Slash icon).
struct ThumbnailView: View {
    let item: FileItem
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if item.isDirectory {
                FolderIconView(url: item.url, isDirectory: true, size: size * 0.8)
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .task(id: item.url) {
            if !item.isDirectory { image = await Thumbnails.image(for: item.url, size: size) }
        }
    }
}

// MARK: - Gallery view (⌘4)

struct GalleryView: View {
    @Environment(AppStore.self) private var store
    let items: [FileItem]
    let pane: Pane
    let open: (URL) -> Void
    let menu: ([URL]) -> AnyView

    private var current: FileItem? {
        items.first { pane.selection.contains($0.url) } ?? items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let current {
                VStack(spacing: 8) {
                    ThumbnailView(item: current, size: 360)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture(count: 2) { open(current.url) }
                    Text(store.displayName(for: current.url)).font(.headline)
                    Text(current.kind).font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .contextMenu { menu([current.url]) }
            } else {
                Text("Empty folder").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(items) { item in
                            ThumbnailView(item: item, size: 72)
                                .padding(4)
                                .background(item.url == current?.url ? Color.accentColor.opacity(0.3) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .id(item.url)
                                .onTapGesture(count: 2) { open(item.url) }
                                .onTapGesture { pane.selection = [item.url] }
                                .contextMenu { menu([item.url]) }
                                .draggable(item.url)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 100)
                .onChange(of: pane.selection) { if let u = current?.url { withAnimation { proxy.scrollTo(u, anchor: .center) } } }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.space) { if let c = current { QuickLook.show(c.url) }; return .handled }
    }

    private func step(_ delta: Int) {
        guard let c = current, let i = items.firstIndex(of: c) else { return }
        let j = min(max(i + delta, 0), items.count - 1)
        pane.selection = [items[j].url]
    }
}

// MARK: - Preview panel (⇧⌘P)

struct PreviewPanel: View {
    let url: URL?
    @State private var pdfSearch = ""

    var body: some View {
        Group {
            if let url {
                let item = FileItem.load(url)
                let type = UTType(filenameExtension: url.pathExtension)
                if type?.conforms(to: .pdf) == true {
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search in PDF", text: $pdfSearch).textFieldStyle(.plain)
                        }
                        .padding(8)
                        Divider()
                        PDFKitView(url: url, search: pdfSearch)
                    }
                } else if type?.conforms(to: .image) == true || type?.conforms(to: .movie) == true {
                    VStack {
                        ThumbnailView(item: item, size: 280)
                        ColumnPreview(item: item)
                    }
                } else if let text = Self.text(of: url, type: type) {
                    ScrollView {
                        Text(text).font(.callout.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }
                } else {
                    ColumnPreview(item: item)
                }
            } else {
                Text("No selection").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: url) { pdfSearch = "" }
    }

    private static func text(of url: URL, type: UTType?) -> String? {
        guard type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 100_000)) ?? Data()
        return String(data: data, encoding: .utf8)
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    let search: String

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        guard let doc = view.document else { return }
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.count >= 2 {
            let found = doc.findString(q, withOptions: .caseInsensitive)
            view.highlightedSelections = found
            if let first = found.first { view.go(to: first) }
        } else {
            view.highlightedSelections = nil
        }
    }
}

// MARK: - PDF tools, archives, sharing

enum PDFTools {
    static func isPDF(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }

    private static func save(_ doc: PDFDocument, name: String, in folder: URL) -> URL? {
        let dest = FileOps.uniqueDestination(for: name, in: folder)
        return doc.write(to: dest) ? dest : nil
    }

    /// Several PDFs → "Combined.pdf" (in the order given).
    static func combine(_ urls: [URL]) {
        let out = PDFDocument()
        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) { out.insert(page, at: out.pageCount) }
            }
        }
        guard let folder = urls.first?.deletingLastPathComponent(), let dest = save(out, name: "Combined.pdf", in: folder) else { return }
        FileUndo.shared.record("Combine PDFs", [.created(dest)])
    }

    /// One PDF → one file per page.
    static func split(_ url: URL) {
        guard let doc = PDFDocument(url: url) else { return }
        let base = url.deletingPathExtension().lastPathComponent
        var created: [UndoOp] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            if let dest = save(single, name: "\(base) - p\(i + 1).pdf", in: url.deletingLastPathComponent()) { created.append(.created(dest)) }
        }
        FileUndo.shared.record("Split PDF", created)
    }

    /// Images → one PDF, a page per image.
    static func fromImages(_ urls: [URL]) {
        let out = PDFDocument()
        for url in urls {
            if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) { out.insert(page, at: out.pageCount) }
        }
        guard out.pageCount > 0, let folder = urls.first?.deletingLastPathComponent(),
              let dest = save(out, name: "Images.pdf", in: folder) else { return }
        FileUndo.shared.record("Create PDF", [.created(dest)])
    }
}

enum Archive {
    /// Like Finder's "Compress": one item → "Name.zip", several → "Archive.zip".
    static func compress(_ urls: [URL]) {
        guard let folder = urls.first?.deletingLastPathComponent() else { return }
        let name = urls.count == 1 ? urls[0].lastPathComponent + ".zip" : "Archive.zip"
        let dest = FileOps.uniqueDestination(for: name, in: folder)
        Task.detached {
            let p = Process()
            if urls.count == 1 {
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, dest.path]
            } else {
                p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                p.currentDirectoryURL = folder
                p.arguments = ["-r", "-q", dest.path] + urls.map(\.lastPathComponent)
            }
            try? p.run()
            p.waitUntilExit()
            let ok = p.terminationStatus == 0
            await MainActor.run {
                if ok { FileUndo.shared.record("Compress", [.created(dest)]) } else { NSSound.beep() }
            }
        }
    }
}

struct OpenWithMenu: View {
    let urls: [URL]

    var body: some View {
        Menu("Open With") {
            if let first = urls.first {
                let apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
                ForEach(apps.prefix(15), id: \.self) { app in
                    Button(FileManager.default.displayName(atPath: app.path)) {
                        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                Divider()
                Button("Other…") {
                    let panel = NSOpenPanel()
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowedContentTypes = [.application]
                    if panel.runModal() == .OK, let app = panel.url {
                        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
        }
    }
}

struct ShareMenu: View {
    let urls: [URL]

    var body: some View {
        Menu("Share") {
            Button("AirDrop") { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls) }
            Button("Mail") { NSSharingService(named: .composeEmail)?.perform(withItems: urls) }
            Button("Messages") { NSSharingService(named: .composeMessage)?.perform(withItems: urls) }
        }
    }
}

enum Deletion {
    /// Deletes without the Trash. Cannot be undone.
    static func deleteImmediately(_ urls: [URL]) {
        let alert = NSAlert()
        alert.messageText = urls.count == 1
            ? "Delete “\(urls[0].lastPathComponent)” immediately?"
            : "Delete \(urls.count) items immediately?"
        alert.informativeText = "The items skip the Trash and can't be recovered from Slash. On Mac SSDs the most reliable protection for sensitive data is FileVault (System Settings ▸ Privacy & Security)."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for url in urls {
            do { try FileManager.default.removeItem(at: url) } catch { NSAlert(error: error).runModal() }
        }
    }
}

// MARK: - Reminders

enum ReminderCenter {
    static let openPathNotification = Notification.Name("SlashOpenPath")

    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            if let path = response.notification.request.content.userInfo["path"] as? String {
                DispatchQueue.main.async { NotificationCenter.default.post(name: ReminderCenter.openPathNotification, object: path) }
            }
            completionHandler()
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }

    private static let delegate = Delegate()

    static func setUp() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func schedule(_ r: FileReminder) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = (r.path as NSString).lastPathComponent
            content.body = r.note.isEmpty ? "Reminder from Slash" : r.note
            content.sound = .default
            content.userInfo = ["path": r.path]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.date)
            let request = UNNotificationRequest(identifier: r.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(request)
        }
    }

    static func cancel(_ r: FileReminder) {
        guard available else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [r.id])
    }
}

struct ReminderSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remind me about “\(store.displayName(for: url))”").font(.headline)
            HStack {
                ForEach([("Tomorrow", 1), ("In a week", 7), ("In a month", 30), ("In 3 months", 90)], id: \.1) { label, days in
                    Button(label) {
                        let base = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                        date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
                    }
                }
            }
            DatePicker("When", selection: $date, in: Date()...)
            TextField("Note (e.g. check the report before sending)", text: $note).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Remind Me") {
                    let r = FileReminder(path: url.path, date: date, note: note)
                    store.reminders.append(r)
                    ReminderCenter.schedule(r)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Folder note (shown under the path bar)

struct FolderNoteBar: View {
    @Environment(AppStore.self) private var store
    let path: String

    var body: some View {
        TextEditor(text: Binding(get: { store.note(for: path) }, set: { store.setNote($0, for: path) }))
            .font(.callout)
            .scrollContentBackground(.hidden)
            .frame(height: 70)
            .padding(6)
            .background(Color.yellow.opacity(0.12))
            .overlay(alignment: .topTrailing) {
                Text("Note · only in Slash").font(.caption2).foregroundStyle(.secondary).padding(4)
            }
    }
}

// MARK: - Downloads: auto-sort rules and recent items

final class DownloadSorter {
    static let shared = DownloadSorter()
    private var watcher: DirectoryWatcher?
    private var pending: DispatchWorkItem?
    private weak var store: AppStore?

    static var downloads: URL { Workspace.folder(.downloadsDirectory) }

    func start(store: AppStore) {
        self.store = store
        watcher = DirectoryWatcher(url: Self.downloads) { [weak self] in self?.schedule() }
        schedule()
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyRules() }
        pending = work
        // Wait a little: browsers write partial files first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Returns how many files were moved.
    @discardableResult
    func applyRules() -> Int {
        guard let store else { return 0 }
        let rules = (store.state.downloadRules ?? []).filter {
            $0.enabled && !$0.destination.isEmpty && !($0.nameContains.isEmpty && $0.fileExtension.isEmpty)
        }
        guard !rules.isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(at: Self.downloads, includingPropertiesForKeys: FileItem.resourceKeys,
                                                                        options: [.skipsHiddenFiles]) else { return 0 }
        let partial: Set<String> = ["download", "crdownload", "part", "partial", "tmp"]
        var moved = 0
        for file in files where !partial.contains(file.pathExtension.lowercased()) {
            let item = FileItem.load(file)
            if let m = item.modified, Date().timeIntervalSince(m) < 3 { continue }
            guard let rule = rules.first(where: { rule in
                (rule.nameContains.isEmpty || file.lastPathComponent.localizedCaseInsensitiveContains(rule.nameContains))
                    && (rule.fileExtension.isEmpty || file.pathExtension.lowercased() == rule.fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }) else { continue }
            let folder = URL(fileURLWithPath: rule.destination)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let dest = FileOps.uniqueDestination(for: file.lastPathComponent, in: folder)
            if (try? FileManager.default.moveItem(at: file, to: dest)) != nil {
                FileUndo.shared.record("Sort Download", [.moved(from: file, to: dest)])
                moved += 1
            }
        }
        return moved
    }

    static func recent(limit: Int = 6) -> [FileItem] {
        let files = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: FileItem.resourceKeys,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return Array(files.map(FileItem.load)
            .sorted { ($0.added ?? $0.modified ?? .distantPast) > ($1.added ?? $1.modified ?? .distantPast) }
            .prefix(limit))
    }
}

struct DownloadRulesSettings: View {
    @Environment(AppStore.self) private var store
    @State private var lastResult: String?

    private var rules: Binding<[DownloadRule]> {
        Binding(get: { store.state.downloadRules ?? [] }, set: { store.state.downloadRules = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New files in Downloads that match a rule are moved automatically.").font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(rules) { $rule in
                    HStack {
                        Toggle("", isOn: $rule.enabled).labelsHidden()
                        TextField("Name contains", text: $rule.nameContains).frame(width: 120)
                        TextField("ext", text: $rule.fileExtension).frame(width: 50)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(rule.destination.isEmpty ? "Choose folder…" : (rule.destination as NSString).lastPathComponent)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(rule.destination.isEmpty ? .secondary : .primary)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK, let url = panel.url { rule.destination = url.path }
                        }
                        Button { rules.wrappedValue.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                Button("Add Rule") { rules.wrappedValue.append(DownloadRule()) }
                Button("Apply Now") {
                    let n = DownloadSorter.shared.applyRules()
                    lastResult = n == 0 ? "Nothing to move" : "Moved \(n) file(s)"
                }
                if let lastResult { Text(lastResult).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding()
    }
}

// MARK: - Private spaces (Touch ID + hidden from screen sharing)

enum PrivacyGuard {
    /// Asks for Touch ID / Apple Watch / password.
    static func unlock(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// Windows of a private space are excluded from screenshots, screen sharing and recordings.
    static func applyWindowSharing(isPrivate: Bool) {
        for window in NSApp.windows {
            window.sharingType = isPrivate ? .none : .readOnly
        }
    }

    static func privatePaths(_ store: AppStore) -> [String] {
        store.state.spaces.filter { $0.isPrivate == true }.flatMap(\.pinnedPaths)
    }

    static func isInsidePrivate(_ path: String, store: AppStore) -> Bool {
        privatePaths(store).contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

// MARK: - Sidebar: locations

enum Locations {
    static func volumes() -> [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey],
                                              options: [.skipHiddenVolumes]) ?? []
    }

    static var trash: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash") }

    static func name(of volume: URL) -> String {
        (try? volume.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? volume.lastPathComponent
    }
}

// MARK: - Quick Actions / Services and Clementine

enum SystemServices {
    /// Quick Actions made with Automator or Shortcuts (~/Library/Services and /Library/Services).
    static func quickActions() -> [String] {
        let dirs = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services"),
                    URL(fileURLWithPath: "/Library/Services")]
        var names: [String] = []
        for dir in dirs {
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for wf in items where wf.pathExtension == "workflow" {
                let plist = wf.appendingPathComponent("Contents/Info.plist")
                guard let dict = NSDictionary(contentsOf: plist) as? [String: Any],
                      let services = dict["NSServices"] as? [[String: Any]],
                      let menu = services.first?["NSMenuItem"] as? [String: Any],
                      let name = menu["default"] as? String else { continue }
                names.append(name)
            }
        }
        return names.sorted()
    }

    /// Runs a Service / Quick Action on files, exactly as Finder's right-click menu would.
    static func run(_ name: String, on urls: [URL]) {
        let pb = NSPasteboard(name: NSPasteboard.Name("SlashService"))
        let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        pb.declareTypes([filenames, .fileURL, .string], owner: nil)
        pb.setPropertyList(urls.map(\.path), forType: filenames)
        if let first = urls.first {
            pb.setString(first.absoluteString, forType: .fileURL)
            pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        }
        if !NSPerformService(name, pb) { NSSound.beep() }
    }
}

enum Clementine {
    static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.stefanoneve.clementine") }

    /// Opens Clementine's wheel for these files, under the mouse pointer.
    static func open(_ urls: [URL]) {
        guard let app = appURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: config)
    }
}

struct ServicesMenu: View {
    let urls: [URL]

    var body: some View {
        if Clementine.appURL != nil {
            Button("Clementine…") { Clementine.open(urls) }
        }
        let actions = SystemServices.quickActions()
        if !actions.isEmpty {
            Menu("Quick Actions") {
                ForEach(actions, id: \.self) { name in
                    Button(name) { SystemServices.run(name, on: urls) }
                }
            }
        }
    }
}
