import Foundation
import Observation

/// Global, persisted app state (spaces, properties, nicknames, folder views...).
/// Tilde keeps the equivalent in several SQLite tables; we keep a single JSON file.
@Observable
final class AppStore {
    var state: PersistedState { didSet { scheduleSave() } }

    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private let fileURL: URL

    /// Where state.json lives: Application Support, or iCloud Drive when "Sync between Macs" is on.
    static func storageDirectory(sync: Bool) -> URL {
        if sync {
            return Workspace.iCloudDrive.appendingPathComponent("Slash", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slash", isDirectory: true)
    }

    static var syncEnabled: Bool { UserDefaults.standard.bool(forKey: "syncWithICloud") }

    /// Copies the data to the other location; the switch takes effect at the next launch.
    func setSync(_ enabled: Bool) {
        let dir = Self.storageDirectory(sync: enabled)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("state.json")
        if !FileManager.default.fileExists(atPath: dest.path), let data = try? JSONEncoder().encode(state) {
            try? data.write(to: dest, options: .atomic)
        }
        UserDefaults.standard.set(enabled, forKey: "syncWithICloud")
    }

    init() {
        let dir = Self.storageDirectory(sync: Self.syncEnabled)
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

    /// Keeps Slash metadata attached when a file or folder (and everything inside it) is renamed/moved in the app.
    func moveMetadata(from old: String, to new: String) {
        var s = state
        func remap<V>(_ dict: inout [String: V]) {
            for key in dict.keys where key == old || key.hasPrefix(old + "/") {
                let newKey = new + key.dropFirst(old.count)
                dict[newKey] = dict.removeValue(forKey: key)
            }
        }
        remap(&s.selections)
        remap(&s.nicknames)
        remap(&s.folderViews)
        if var icons = s.folderIcons { remap(&icons); s.folderIcons = icons }
        if var notes = s.folderNotes { remap(&notes); s.folderNotes = notes }
        remap(&s.relations)
        s.reminders = s.reminders?.map { r in
            var r = r
            if r.path == old || r.path.hasPrefix(old + "/") { r.path = new + r.path.dropFirst(old.count) }
            return r
        }
        for i in s.spaces.indices {
            s.spaces[i].pinnedPaths = s.spaces[i].pinnedPaths.map { p in
                p == old || p.hasPrefix(old + "/") ? new + p.dropFirst(old.count) : p
            }
        }
        state = s
    }

    // MARK: Templates

    static let defaultTemplates = [
        FolderTemplate(name: "Nuovo caso",
                       subfolders: ["Anamnesi", "Test", "Relazioni", "Comunicazioni scuola", "Consensi"],
                       icon: FolderIcon(symbol: "person.fill", color: .blue))
    ]

    var templates: [FolderTemplate] {
        get { state.templates ?? Self.defaultTemplates }
        set { state.templates = newValue }
    }

    /// Creates `name` inside `parent` with the template's subfolders and icon. Returns the new folder.
    func createFromTemplate(_ template: FolderTemplate, named name: String, in parent: URL) throws -> URL {
        let root = FileOps.uniqueDestination(for: name, in: parent)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        for sub in template.subfolders {
            let clean = sub.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { continue }
            try FileManager.default.createDirectory(at: root.appendingPathComponent(clean), withIntermediateDirectories: true)
        }
        if let icon = template.icon { setIcon(icon, for: root.path) }
        return root
    }

    // MARK: Smart folders

    var smartFolders: [SmartFolder] {
        get { state.smartFolders ?? [] }
        set { state.smartFolders = newValue }
    }

    /// Runs a smart folder's search. Property criteria come from Slash's own data (instant);
    /// name / date criteria scan the Space's pinned folders.
    func results(for smart: SmartFolder) async -> [FileItem] {
        let selections = state.selections
        let roots = (state.spaces.first { $0.id == smart.spaceID } ?? currentSpace)?.pinnedPaths ?? []
        return await Task.detached(priority: .utility) {
            let cutoff = smart.modifiedWithinDays.map { Date().addingTimeInterval(-Double($0) * 86400) }
            let name = smart.nameContains?.trimmingCharacters(in: .whitespaces) ?? ""
            func matches(_ item: FileItem) -> Bool {
                if !name.isEmpty, !item.name.localizedCaseInsensitiveContains(name) { return false }
                if let cutoff, (item.modified ?? .distantPast) < cutoff { return false }
                return true
            }
            if let prop = smart.propertyID, let opt = smart.optionID {
                return selections
                    .filter { $0.value[prop] == opt && FileManager.default.fileExists(atPath: $0.key) }
                    .map { FileItem.load(URL(fileURLWithPath: $0.key)) }
                    .filter(matches)
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            var out: [FileItem] = []
            for root in roots {
                guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: FileItem.resourceKeys,
                                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in e {
                    let item = FileItem.load(url)
                    if matches(item) { out.append(item) }
                    if out.count >= 500 { break }
                }
            }
            return out.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        }.value
    }

    // MARK: Notes, reminders, related items

    func note(for path: String) -> String { state.folderNotes?[path] ?? "" }

    func setNote(_ text: String, for path: String) {
        var notes = state.folderNotes ?? [:]
        notes[path] = text.isEmpty ? nil : text
        state.folderNotes = notes
    }

    var reminders: [FileReminder] {
        get { state.reminders ?? [] }
        set { state.reminders = newValue }
    }

    func relations(for path: String) -> FolderRelations { state.relations[path] ?? FolderRelations() }

    /// Links two folders both ways.
    func relate(_ a: String, _ b: String) {
        guard a != b else { return }
        var ra = relations(for: a), rb = relations(for: b)
        if !ra.relatedPaths.contains(b) { ra.relatedPaths.append(b) }
        if !rb.relatedPaths.contains(a) { rb.relatedPaths.append(a) }
        state.relations[a] = ra
        state.relations[b] = rb
    }

    func unrelate(_ a: String, _ b: String) {
        state.relations[a]?.relatedPaths.removeAll { $0 == b }
        state.relations[b]?.relatedPaths.removeAll { $0 == a }
    }

    func addLink(_ link: String, to path: String) {
        var r = relations(for: path)
        if !r.urls.contains(link) { r.urls.append(link) }
        state.relations[path] = r
    }

    func removeLink(_ link: String, from path: String) {
        state.relations[path]?.urls.removeAll { $0 == link }
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
