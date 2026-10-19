import Foundation
import Observation

/// Global, persisted app state (spaces, properties, nicknames, folder views...).
/// Tilde keeps the equivalent in several SQLite tables; we keep a single JSON file.
@Observable
final class AppStore {
    var state: PersistedState { didSet { scheduleSave() } }

    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("state.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            state = decoded
        } else {
            state = AppStore.defaultState()
        }
    }

    private static func defaultState() -> PersistedState {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var s = PersistedState()
        let personal = Space(
            name: "Personal",
            symbol: "person",
            pinnedPaths: ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0).path }
        )
        s.spaces = [personal]
        s.selectedSpaceID = personal.id
        s.properties = [
            PropertyDefinition(name: "Status", options: [
                PropertyOption(name: "To do", color: .gray),
                PropertyOption(name: "In progress", color: .orange),
                PropertyOption(name: "Done", color: .green)
            ])
        ]
        return s
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = state
        let url = fileURL
        let work = DispatchWorkItem {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Spaces

    var currentSpace: Space? {
        state.spaces.first { $0.id == state.selectedSpaceID } ?? state.spaces.first
    }

    func updateCurrentSpace(_ change: (inout Space) -> Void) {
        guard let id = currentSpace?.id, let i = state.spaces.firstIndex(where: { $0.id == id }) else { return }
        change(&state.spaces[i])
    }

    func addSpace(named name: String) {
        let s = Space(name: name)
        state.spaces.append(s)
        state.selectedSpaceID = s.id
    }

    func pin(_ path: String) {
        updateCurrentSpace { if !$0.pinnedPaths.contains(path) { $0.pinnedPaths.append(path) } }
    }

    func unpin(_ path: String) {
        updateCurrentSpace { $0.pinnedPaths.removeAll { $0 == path } }
    }

    // MARK: Nicknames

    func displayName(for url: URL) -> String {
        state.nicknames[url.path] ?? url.lastPathComponent
    }

    func setNickname(_ name: String?, for path: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        state.nicknames[path] = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Properties

    func option(for path: String, property: PropertyDefinition) -> PropertyOption? {
        property.option(state.selections[path]?[property.id])
    }

    func setOption(_ optionID: String?, property propertyID: String, for paths: [String]) {
        for p in paths {
            var sel = state.selections[p] ?? [:]
            sel[propertyID] = optionID
            state.selections[p] = sel.isEmpty ? nil : sel
        }
    }

    /// Keeps properties attached when a file is renamed/moved inside the app.
    func moveMetadata(from old: String, to new: String) {
        if let s = state.selections.removeValue(forKey: old) { state.selections[new] = s }
        if let n = state.nicknames.removeValue(forKey: old) { state.nicknames[new] = n }
        if let v = state.folderViews.removeValue(forKey: old) { state.folderViews[new] = v }
        if let i = state.folderIcons?.removeValue(forKey: old) { state.folderIcons?[new] = i }
    }

    // MARK: Folder views

    func viewSet(for folder: String) -> FolderViewSet {
        state.folderViews[folder] ?? FolderViewSet()
    }

    func setViewSet(_ set: FolderViewSet, for folder: String) {
        state.folderViews[folder] = set
    }

    // MARK: Folder icons

    func icon(for path: String) -> FolderIcon? {
        state.folderIcons?[path]
    }

    func setIcon(_ icon: FolderIcon?, for path: String) {
        var icons = state.folderIcons ?? [:]
        icons[path] = icon
        state.folderIcons = icons
    }

    // MARK: Recents

    func noteVisited(_ path: String) {
        var r = state.recentFolders.filter { $0 != path }
        r.insert(path, at: 0)
        if r.count > 50 { r = Array(r.prefix(50)) }
        if r != state.recentFolders { state.recentFolders = r }
    }
}
