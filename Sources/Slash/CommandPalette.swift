import SwiftUI
import AppKit

/// ⌘K: jump to any folder or file in the current space, recent folders, or run an action.
struct CommandPaletteView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace

    @State private var query = ""
    @State private var index: [URL] = []
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let run: () -> Void
    }

    private var entries: [Entry] {
        var out: [Entry] = []
        let q = query.trimmingCharacters(in: .whitespaces)

        let actions: [(String, String, () -> Void)] = [
            ("Split Pane", "rectangle.split.2x1", { workspace.split() }),
            ("New Tab", "plus.square.on.square", { workspace.open(workspace.focusedPane.activeTab.url, newTab: true) }),
            ("Pin Current Folder", "pin", { store.pin(workspace.focusedPane.activeTab.url.path) }),
            ("Go Home", "house", { workspace.open(FileManager.default.homeDirectoryForCurrentUser) }),
            ("Check for Updates", "arrow.down.circle", { Updater.shared.checkNow() })
        ]
        for (title, icon, run) in actions where q.isEmpty || Fuzzy.score(title, q) != nil {
            out.append(Entry(id: "a:" + title, title: title, subtitle: "Action", icon: icon, run: run))
        }

        var seen = Set<String>()
        var candidates = store.state.recentFolders.map { URL(fileURLWithPath: $0) } + index
        if q.isEmpty { candidates = Array(candidates.prefix(20)) }
        let scored: [(URL, Int)] = candidates.compactMap { url in
            guard !seen.contains(url.path) else { return nil }
            seen.insert(url.path)
            if q.isEmpty { return (url, 0) }
            let name = store.displayName(for: url)
            guard let s = Fuzzy.score(name, q) else { return nil }
            return (url, s)
        }
        for (url, _) in scored.sorted(by: { $0.1 > $1.1 }).prefix(40) {
            let isDir = FileItem.load(url).isDirectory
            out.append(Entry(
                id: url.path,
                title: store.displayName(for: url),
                subtitle: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                icon: isDir ? "folder" : "doc",
                run: {
                    if isDir { workspace.open(url) } else { NSWorkspace.shared.open(url) }
                }
            ))
        }
        return out
    }

    var body: some View {
        let list = entries
        VStack(spacing: 0) {
            TextField("Go to folder, file or action…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .focused($focused)
                .onSubmit { activate(list) }
                .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(list.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        HStack {
                            Image(systemName: e.icon).frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(e.title)
                                Text(e.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(i == highlighted ? Color.accentColor.opacity(0.25) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { highlighted = i; activate(list) }
                        .id(i)
                    }
                }
                .listStyle(.plain)
                .onChange(of: highlighted) { _, v in proxy.scrollTo(v) }
            }
        }
        .frame(width: 560, height: 400)
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
        .task {
            let roots = (store.currentSpace?.pinnedPaths ?? []).map { URL(fileURLWithPath: $0) }
            index = await Task.detached(priority: .userInitiated) { PaletteIndex.build(roots) }.value
        }
    }

    private func activate(_ list: [Entry]) {
        guard list.indices.contains(highlighted) else { return }
        let e = list[highlighted]
        dismiss()
        e.run()
    }
}

enum PaletteIndex {
    static func build(_ roots: [URL], limit: Int = 20000) -> [URL] {
        var out: [URL] = []
        for root in roots {
            out.append(root)
            guard let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in e {
                if e.level > 5 { e.skipDescendants(); continue }
                out.append(url)
                if out.count >= limit { return out }
            }
        }
        return out
    }
}

enum Fuzzy {
    /// Subsequence match; higher is better. nil = no match.
    static func score(_ text: String, _ query: String) -> Int? {
        let t = Array(text.lowercased()), q = Array(query.lowercased())
        if q.isEmpty { return 0 }
        var ti = 0, score = 0, streak = 0
        for c in q {
            var found = false
            while ti < t.count {
                if t[ti] == c {
                    streak += 1
                    score += 1 + streak * 2 + (ti == 0 ? 5 : 0)
                    ti += 1
                    found = true
                    break
                }
                streak = 0
                ti += 1
            }
            if !found { return nil }
        }
        return score - t.count / 4
    }
}
