import Foundation
import AppKit
import Observation

// MARK: - Undo (⌘Z) for file operations

enum UndoOp {
    /// Undo: move `to` back to `from`
    case moved(from: URL, to: URL)
    /// Undo: put `URL` in the Trash
    case created(URL)
    /// Undo: put the item back from the Trash
    case trashed(original: URL, trashed: URL)
}

@Observable
final class FileUndo {
    static let shared = FileUndo()
    private var stack: [(name: String, ops: [UndoOp])] = []

    var canUndo: Bool { !stack.isEmpty }
    var undoTitle: String { stack.last.map { "Undo \($0.name)" } ?? "Undo" }

    func record(_ name: String, _ ops: [UndoOp]) {
        guard !ops.isEmpty else { return }
        stack.append((name, ops))
        if stack.count > 50 { stack.removeFirst() }
    }

    func undo(store: AppStore?) {
        guard let last = stack.popLast() else { NSSound.beep(); return }
        let fm = FileManager.default
        for op in last.ops.reversed() {
            do {
                switch op {
                case let .moved(from, to):
                    try fm.moveItem(at: to, to: from)
                    store?.moveMetadata(from: to.path, to: from.path)
                case let .created(url):
                    try fm.trashItem(at: url, resultingItemURL: nil)
                case let .trashed(original, trashed):
                    try fm.moveItem(at: trashed, to: original)
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

// MARK: - Copy / move with progress and conflict handling

@Observable
final class FileTransfer {
    static let shared = FileTransfer()

    private(set) var isRunning = false
    private(set) var title = ""
    private(set) var currentName = ""
    private(set) var fraction: Double = 0
    @ObservationIgnored private var cancelled = false

    private enum Choice { case replace, keepBoth, skip, stop }

    func cancel() { cancelled = true }

    /// Copies or moves items into `folder`. Must be called on the main thread.
    func run(_ urls: [URL], to folder: URL, copy: Bool, store: AppStore?) {
        let fm = FileManager.default
        let sources = urls.filter { src in
            src.standardizedFileURL != folder.standardizedFileURL
                && !folder.standardizedFileURL.path.hasPrefix(src.standardizedFileURL.path + "/")
                && (copy || src.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL)
        }

        // Decide conflicts up front, like Finder ("Keep Both / Replace / Skip", with "Apply to all").
        var plan: [(src: URL, dest: URL, replace: Bool)] = []
        var applyToAll: Choice?
        for (i, src) in sources.enumerated() {
            var dest = folder.appendingPathComponent(src.lastPathComponent)
            var replace = false
            if fm.fileExists(atPath: dest.path) {
                let choice = applyToAll ?? askConflict(name: src.lastPathComponent, more: i < sources.count - 1, applyToAll: &applyToAll)
                switch choice {
                case .stop: return
                case .skip: continue
                case .keepBoth: dest = FileOps.uniqueDestination(for: src.lastPathComponent, in: folder)
                case .replace: replace = true
                }
            }
            plan.append((src, dest, replace))
        }
        guard !plan.isEmpty else { return }

        isRunning = true
        cancelled = false
        fraction = 0
        title = copy ? "Copying" : "Moving"
        let opName = copy ? "Copy" : "Move"

        Task.detached(priority: .userInitiated) {
            let sizes = plan.map { FileTransfer.size(of: $0.src) }
            let total = max(sizes.reduce(0, +), 1)
            var done: Int64 = 0
            var ops: [UndoOp] = []
            var firstError: Error?

            for (index, step) in plan.enumerated() {
                if self.cancelled { break }
                await MainActor.run { self.currentName = step.src.lastPathComponent }
                do {
                    if step.replace {
                        var trashed: NSURL?
                        try fm.trashItem(at: step.dest, resultingItemURL: &trashed)
                        if let t = trashed as URL? { ops.append(.trashed(original: step.dest, trashed: t)) }
                    }
                    if copy {
                        try fm.copyItem(at: step.src, to: step.dest)
                        ops.append(.created(step.dest))
                    } else {
                        try fm.moveItem(at: step.src, to: step.dest)
                        ops.append(.moved(from: step.src, to: step.dest))
                        await MainActor.run { store?.moveMetadata(from: step.src.path, to: step.dest.path) }
                    }
                } catch {
                    if firstError == nil { firstError = error }
                }
                done += sizes[index]
                let f = Double(done) / Double(total)
                await MainActor.run { self.fraction = f }
            }

            let finishedOps = ops
            let err = firstError
            await MainActor.run {
                self.isRunning = false
                FileUndo.shared.record(opName, finishedOps)
                if let err { NSAlert(error: err).runModal() }
            }
        }
    }

    private func askConflict(name: String, more: Bool, applyToAll: inout Choice?) -> Choice {
        let alert = NSAlert()
        alert.messageText = "An item named “\(name)” already exists in this location."
        alert.informativeText = "Do you want to replace it with the one you're copying?"
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Stop")
        if more {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Apply to all"
        }
        let choice: Choice
        switch alert.runModal() {
        case .alertFirstButtonReturn: choice = .keepBoth
        case .alertSecondButtonReturn: choice = .replace
        case .alertThirdButtonReturn: choice = .skip
        default: return .stop
        }
        if alert.suppressionButton?.state == .on { applyToAll = choice }
        return choice
    }

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard v.isDirectory == true else { return Int64(v.fileSize ?? 0) }
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
            for case let child as URL in e {
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return total
    }
}

// MARK: - Spotlight search (names + contents)

enum SpotlightSearch {
    private final class Box {
        var token: NSObjectProtocol?
        var finished = false
    }

    /// Finds files under `scope` whose name or text content contains `text`.
    static func find(_ text: String, in scope: URL, limit: Int = 2000) async -> [URL] {
        await withCheckedContinuation { (cont: CheckedContinuation<[URL], Never>) in
            DispatchQueue.main.async {
                let query = NSMetadataQuery()
                query.searchScopes = [scope]
                query.predicate = NSPredicate(
                    format: "%K CONTAINS[cd] %@ OR %K CONTAINS[cd] %@",
                    NSMetadataItemFSNameKey, text, "kMDItemTextContent", text
                )
                let box = Box()
                let finish = {
                    guard !box.finished else { return }
                    box.finished = true
                    query.stop()
                    if let token = box.token { NotificationCenter.default.removeObserver(token) }
                    var urls: [URL] = []
                    for case let item as NSMetadataItem in query.results {
                        if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                            urls.append(URL(fileURLWithPath: path))
                            if urls.count >= limit { break }
                        }
                    }
                    cont.resume(returning: urls)
                }
                box.token = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
                ) { _ in finish() }
                if !query.start() { finish() }
                // Folders that Spotlight doesn't index (some cloud drives) never finish: give up after 5 s.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish() }
            }
        }
    }
}
