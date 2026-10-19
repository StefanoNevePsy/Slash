import Foundation
import AppKit

/// Finder-style file commands, run against the focused pane. Used by menus, shortcuts and context menus.
extension Workspace {
    /// Where new folders / pasted files go: the deepest selected folder in column view, else the tab's folder.
    var currentFolder: URL { focusedPane.columnPath.last ?? focusedPane.activeTab.url }

    /// Selected items, in a stable order.
    var selectedURLs: [URL] { focusedPane.selection.sorted { $0.path < $1.path } }

    /// True while the user is typing in a text field: then ⌘C/⌘V/⌘A/⌘⌫ must go to the text, not to files.
    static var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    func openSelection() {
        for url in selectedURLs {
            if FileItem.load(url).isDirectory { open(url) } else { NSWorkspace.shared.open(url) }
        }
    }

    func copySelection() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }

    /// ⌘V copies, ⌥⌘V moves (exactly like Finder).
    func paste(move: Bool) {
        guard let store,
              let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return }
        FileOps.move(urls, to: currentFolder, copy: !move, store: store)
    }

    /// ⌘D: "Name copy.ext", like Finder.
    func duplicateSelection() {
        var created: Set<URL> = []
        for src in selectedURLs {
            let folder = src.deletingLastPathComponent()
            let base = src.deletingPathExtension().lastPathComponent
            let ext = src.pathExtension
            var n = 1
            var dest: URL
            repeat {
                let suffix = n == 1 ? " copy" : " copy \(n)"
                dest = folder.appendingPathComponent(base + suffix + (ext.isEmpty ? "" : ".\(ext)"))
                n += 1
            } while FileManager.default.fileExists(atPath: dest.path)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                created.insert(dest)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        FileUndo.shared.record("Duplicate", created.map { .created($0) })
        if !created.isEmpty { focusedPane.selection = created }
    }

    func trashSelection() {
        var ops: [UndoOp] = []
        for url in selectedURLs {
            do {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                if let t = trashed as URL? { ops.append(.trashed(original: url, trashed: t)) }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        FileUndo.shared.record("Move to Trash", ops)
        focusedPane.selection = []
    }

    func newFolder() {
        let folder = currentFolder
        var url = folder.appendingPathComponent("untitled folder")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("untitled folder \(n)"); n += 1
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            FileUndo.shared.record("New Folder", [.created(url)])
            focusedPane.selection = [url]
            focusedPane.renaming = url
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func beginRename() {
        guard focusedPane.selection.count == 1 else { return }
        focusedPane.renaming = focusedPane.selection.first
    }

    /// Renames on disk, keeping Slash metadata (properties, nickname, icon) attached.
    func rename(_ url: URL, to newName: String) {
        focusedPane.renaming = nil
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != url.lastPathComponent, !name.contains("/") else { return }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            store?.moveMetadata(from: url.path, to: dest.path)
            FileUndo.shared.record("Rename", [.moved(from: url, to: dest)])
            focusedPane.selection = [dest]
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// ⌘I: the real Finder "Get Info" window.
    func getInfo() {
        let urls = selectedURLs.isEmpty ? [currentFolder] : selectedURLs
        for url in urls {
            let path = url.path.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Finder"
                activate
                open information window of (POSIX file "\(path)" as alias)
            end tell
            """
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
    }

    func makeAlias() {
        for src in selectedURLs {
            let dest = FileOps.uniqueDestination(for: src.lastPathComponent + " alias", in: src.deletingLastPathComponent())
            do {
                let data = try src.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(data, to: dest)
                FileUndo.shared.record("Make Alias", [.created(dest)])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func showOriginal() {
        guard let url = selectedURLs.first,
              let original = try? URL(resolvingAliasFileAt: url),
              original != url else { return }
        open(original.deletingLastPathComponent())
        focusedPane.selection = [original]
    }

    func ejectSelection() {
        for url in selectedURLs {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
        }
    }

    // MARK: View

    private func updateActiveView(_ change: (inout FolderView) -> Void) {
        guard let store else { return }
        let path = currentFolder.path
        var set = store.viewSet(for: path)
        var v = set.active
        change(&v)
        set.active = v
        store.setViewSet(set, for: path)
    }

    func setViewMode(_ mode: ViewMode) {
        updateActiveView { $0.mode = mode }
        focusedPane.columnPath = []
    }

    func sort(by key: SortKey) {
        updateActiveView { v in
            if v.sortKey == key { v.ascending.toggle() } else { v.sortKey = key; v.ascending = key == .name || key == .kind || key == .tags }
        }
    }

    func group(by key: GroupKey?) {
        updateActiveView { $0.groupKey = key; if key != nil { $0.groupByPropertyID = nil } }
    }

    /// ⌃⌘0: "Use Groups" on/off (defaults to Kind, like Finder).
    func toggleGroups() {
        updateActiveView { v in
            if v.groupKey != nil || v.groupByPropertyID != nil {
                v.groupKey = nil
                v.groupByPropertyID = nil
            } else {
                v.groupKey = .kind
            }
        }
    }

    func toggleHidden() {
        updateActiveView { $0.showHidden.toggle() }
    }

    // MARK: Places

    static func folder(_ dir: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: dir, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }
}
