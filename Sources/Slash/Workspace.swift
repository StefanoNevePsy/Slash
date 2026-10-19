import Foundation
import Observation

/// Watches a single directory and calls back when its contents change.
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?

    init?(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .attrib], queue: .main
        )
        src.setEventHandler(handler: onChange)
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}

/// One tab inside a pane, with its own back/forward history.
@Observable
final class FolderTab: Identifiable {
    let id = UUID()
    private(set) var url: URL
    private(set) var items: [FileItem] = []
    private(set) var error: String?
    private var back: [URL] = []
    private var forward: [URL] = []

    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored weak var store: AppStore?

    init(url: URL, store: AppStore?) {
        self.url = url
        self.store = store
        load()
    }

    var title: String { store?.displayName(for: url) ?? url.lastPathComponent }
    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    func navigate(to newURL: URL) {
        guard newURL != url else { return }
        back.append(url)
        forward.removeAll()
        url = newURL
        load()
    }

    func goBack() {
        guard let prev = back.popLast() else { return }
        forward.append(url)
        url = prev
        load()
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(url)
        url = next
        load()
    }

    func goUp() {
        let parent = url.deletingLastPathComponent()
        if parent.path != url.path { navigate(to: parent) }
    }

    func reload() { load(rewatch: false) }

    private func load(rewatch: Bool = true) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: FileItem.resourceKeys,
                options: []
            )
            items = urls.map(FileItem.load)
            error = nil
        } catch {
            items = []
            self.error = error.localizedDescription
        }
        if rewatch {
            watcher = DirectoryWatcher(url: url) { [weak self] in self?.reload() }
            store?.noteVisited(url.path)
        }
    }
}

/// A split pane: a strip of tabs, one of them active.
@Observable
final class Pane: Identifiable {
    let id = UUID()
    var tabs: [FolderTab]
    var activeTabID: UUID
    var selection: Set<URL> = []
    /// Item being renamed inline (Return key, like Finder)
    var renaming: URL?
    var showViewOptions = false
    /// ⌘F search inside this pane
    var searchText = ""
    var searchActive = false
    var searchSubfolders = false
    /// Column view: folders selected to the right of the tab's folder
    var columnPath: [URL] = []

    init(url: URL, store: AppStore?) {
        let t = FolderTab(url: url, store: store)
        tabs = [t]
        activeTabID = t.id
    }

    var activeTab: FolderTab { tabs.first { $0.id == activeTabID } ?? tabs[0] }

    func openTab(_ url: URL, store: AppStore?) {
        let t = FolderTab(url: url, store: store)
        if let i = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs.insert(t, at: i + 1)
        } else {
            tabs.append(t)
        }
        activeTabID = t.id
        selection = []
    }

    /// Returns false when this was the last tab (caller may close the pane).
    @discardableResult
    func closeTab(_ id: UUID) -> Bool {
        guard tabs.count > 1, let i = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs.remove(at: i)
        if activeTabID == id { activeTabID = tabs[min(i, tabs.count - 1)].id }
        return true
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }
}

/// Everything in one window: panes laid out side by side, plus which one has focus.
@Observable
final class Workspace {
    var panes: [Pane]
    var focusedPaneID: UUID
    var showPalette = false
    var showGoToFolder = false
    var showConnectToServer = false
    @ObservationIgnored weak var store: AppStore?

    init(store: AppStore) {
        self.store = store
        if let restored = Workspace.restoredPanes(store: store) {
            panes = restored.panes
            focusedPaneID = restored.panes[min(restored.focused, restored.panes.count - 1)].id
            return
        }
        let start = store.currentSpace?.pinnedPaths.first.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let p = Pane(url: start, store: store)
        panes = [p]
        focusedPaneID = p.id
    }

    // MARK: Session (panes & tabs come back after quitting)

    struct Session: Codable, Equatable {
        var panes: [[String]]
        var activeTabs: [Int]
        var focused: Int
    }

    private static let sessionKey = "lastSession"

    var session: Session {
        Session(
            panes: panes.map { $0.tabs.map(\.url.path) },
            activeTabs: panes.map { p in p.tabs.firstIndex { $0.id == p.activeTabID } ?? 0 },
            focused: panes.firstIndex { $0.id == focusedPaneID } ?? 0
        )
    }

    func saveSession() {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
    }

    private static func restoredPanes(store: AppStore) -> (panes: [Pane], focused: Int)? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let s = try? JSONDecoder().decode(Session.self, from: data) else { return nil }
        let fm = FileManager.default
        var panes: [Pane] = []
        for (i, paths) in s.panes.enumerated() {
            let existing = paths.filter { fm.fileExists(atPath: $0) }
            guard let first = existing.first else { continue }
            let pane = Pane(url: URL(fileURLWithPath: first), store: store)
            for path in existing.dropFirst() { pane.openTab(URL(fileURLWithPath: path), store: store) }
            let active = i < s.activeTabs.count ? s.activeTabs[i] : 0
            if pane.tabs.indices.contains(active) { pane.activeTabID = pane.tabs[active].id }
            panes.append(pane)
        }
        return panes.isEmpty ? nil : (panes, s.focused)
    }

    var focusedPane: Pane { panes.first { $0.id == focusedPaneID } ?? panes[0] }

    func open(_ url: URL, newTab: Bool = false) {
        if newTab {
            focusedPane.openTab(url, store: store)
        } else {
            focusedPane.activeTab.navigate(to: url)
            focusedPane.selection = []
        }
    }

    func split() {
        guard panes.count < 4 else { return }
        let p = Pane(url: focusedPane.activeTab.url, store: store)
        if let i = panes.firstIndex(where: { $0.id == focusedPaneID }) {
            panes.insert(p, at: i + 1)
        } else {
            panes.append(p)
        }
        focusedPaneID = p.id
    }

    func closePane(_ id: UUID) {
        guard panes.count > 1, let i = panes.firstIndex(where: { $0.id == id }) else { return }
        panes.remove(at: i)
        if focusedPaneID == id { focusedPaneID = panes[max(0, i - 1)].id }
    }

    func closeActiveTab() {
        let pane = focusedPane
        if !pane.closeTab(pane.activeTabID) { closePane(pane.id) }
    }

    /// The pane next to the focused one (used for "Open in other pane" / copy & move).
    var otherPane: Pane? {
        guard panes.count > 1, let i = panes.firstIndex(where: { $0.id == focusedPaneID }) else { return nil }
        return panes[(i + 1) % panes.count]
    }
}
