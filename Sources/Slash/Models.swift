import Foundation
import CoreServices
import SwiftUI

// MARK: - File system

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?
    let created: Date?
    let added: Date?
    let isHidden: Bool
    /// Localized kind, as shown by Finder ("PDF document", "Folder"...)
    let kind: String
    /// Finder tags
    let tags: [String]

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var path: String { url.path }

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
        .addedToDirectoryDateKey, .isHiddenKey, .isPackageKey, .localizedTypeDescriptionKey, .tagNamesKey
    ]

    static func load(_ url: URL) -> FileItem {
        let v = try? url.resourceValues(forKeys: Set(resourceKeys))
        let isDir = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
        return FileItem(
            url: url,
            isDirectory: isDir,
            size: v?.fileSize.map(Int64.init),
            modified: v?.contentModificationDate,
            created: v?.creationDate,
            added: v?.addedToDirectoryDate,
            isHidden: v?.isHidden ?? url.lastPathComponent.hasPrefix("."),
            kind: v?.localizedTypeDescription ?? (isDir ? "Folder" : "Document"),
            tags: v?.tagNames ?? []
        )
    }

    /// "Date Last Opened" as Finder shows it (from Spotlight metadata).
    static func lastOpened(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

// MARK: - Spaces & sidebar

struct Space: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String = "square.stack"
    var pinnedPaths: [String] = []
    /// Space-wide links (shown in the Overview page)
    var links: [String] = []
}

// MARK: - Properties (custom metadata)

struct PropertyOption: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name: String
    var color: PropertyColor = .blue
}

enum PropertyColor: String, Codable, CaseIterable {
    case gray, red, orange, yellow, green, teal, blue, purple, pink

    var color: Color {
        switch self {
        case .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

struct PropertyDefinition: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name: String
    var options: [PropertyOption] = []

    func option(_ id: String?) -> PropertyOption? {
        guard let id else { return nil }
        return options.first { $0.id == id }
    }
}

// MARK: - Folder views (sort / group / filter per folder)

/// Same criteria as Finder's View ▸ Sort By.
enum SortKey: String, Codable, CaseIterable, Identifiable {
    case name, kind, lastOpened, added, modified, created, size, tags
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: "Name"
        case .kind: "Kind"
        case .lastOpened: "Date Last Opened"
        case .added: "Date Added"
        case .modified: "Date Modified"
        case .created: "Date Created"
        case .size: "Size"
        case .tags: "Tags"
        }
    }
}

/// Same criteria as Finder's View ▸ Use Groups / Group By.
enum GroupKey: String, Codable, CaseIterable, Identifiable {
    case kind, lastOpened, added, modified, created, size, tags
    var id: String { rawValue }
    var label: String { SortKey(rawValue: rawValue)?.label ?? rawValue }
}

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case icons, list, columns
    var id: String { rawValue }
    var label: String {
        switch self {
        case .icons: "Icons"
        case .list: "List"
        case .columns: "Columns"
        }
    }
    var symbol: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .list: "list.bullet"
        case .columns: "rectangle.split.3x1"
        }
    }
}

struct FolderView: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var title: String = "Default"
    var sortKey: SortKey = .name
    var ascending = true
    var foldersFirst = true
    var showHidden = false
    /// Group rows by the option chosen for this property
    var groupByPropertyID: String?
    /// Group rows by a Finder criterion (takes precedence over groupByPropertyID). Optional for old state files.
    var groupKey: GroupKey?
    /// Icons / List / Columns. Optional for old state files (nil = list).
    var mode: ViewMode?
    /// propertyID -> optionID. Only items matching all filters are shown.
    var filters: [String: String] = [:]
}

struct FolderViewSet: Codable, Hashable {
    var views: [FolderView] = [FolderView()]
    var activeID: String?

    var active: FolderView {
        get { views.first { $0.id == activeID } ?? views[0] }
        set {
            if let i = views.firstIndex(where: { $0.id == newValue.id }) { views[i] = newValue }
        }
    }
}

// MARK: - Custom folder icons

/// An SF Symbol + color chosen for a folder. Stored in Slash, so it also works on Google Drive / iCloud folders.
struct FolderIcon: Codable, Hashable {
    var symbol: String
    var color: PropertyColor = .blue
}

// MARK: - Related items

struct FolderRelations: Codable, Hashable {
    var relatedPaths: [String] = []
    var urls: [String] = []
}

// MARK: - Persisted state

struct PersistedState: Codable {
    var spaces: [Space] = []
    var selectedSpaceID: UUID?
    var properties: [PropertyDefinition] = []
    /// itemPath -> (propertyID -> optionID)
    var selections: [String: [String: String]] = [:]
    var nicknames: [String: String] = [:]
    var folderViews: [String: FolderViewSet] = [:]
    var relations: [String: FolderRelations] = [:]
    var recentFolders: [String] = []
    /// Optional so state files saved by older versions still load.
    var folderIcons: [String: FolderIcon]?
}
