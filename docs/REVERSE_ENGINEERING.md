# Tilde for Mac — analisi (reverse engineering statico)

Fonte: `https://download.tildeformac.com/latest` (Tilde 0.9.1, build 10, 2026-09-28), DMG estratto con 7-Zip.
Analisi statica di `Info.plist`, framework inclusi e stringhe del binario Mach-O arm64. Nessun codice è stato copiato.

## Cosa abbiamo scoperto
- **Stack**: Swift, SwiftUI + AppKit (molte `NSTableView`, `NSSplitView`, `NSHostingView`), macOS 14+, solo Apple silicon.
- **Bundle id**: `com.blazegreenhalgh.FileExplorer` (nome interno precedente: *Wayfinder*).
- **Librerie**: Sparkle (aggiornamenti), Bonsplit (split/tab), HighlighterSwift (anteprima codice), libwebp.
- **Persistenza**: SQLite. Tabelle trovate: `folder_file_views` (viste per cartella: view_mode, sort/group/filter descriptors, colonne),
  `file_properties` + `file_property_selections` (proprietà custom: definizioni JSON + selezione per path),
  `folder_file_properties`, `file_nicknames` (path → nickname), `sidebar_state` (gruppi sidebar in JSON),
  `tab_sessions`, `space_home_pages` (pagina Overview per Space), `folder_relations` + `folder_related_urls`
  (cartelle collegate con bookmark), `recent_folders`, più due cache: `DirectoryListingCache.sqlite3` e `CommandPaletteFolderIndex.sqlite3`.
- **Componenti**: `ColumnPane*` (vista a colonne), `CommandPaletteFolderIndex` / `CommandPaletteUsageStore` (indice + frequenza d'uso),
  `SidebarLiveGroupController` (Live Groups), `QuickLookPanelController`, `ImageOperationService`, `DownloadsTrayStore`,
  `FinderAuthorizedFileOperationService` (usa AppleEvents verso Finder per operazioni che richiedono privilegi),
  `FileExplorerPicker*` (inietta percorsi nei dialoghi Apri/Salva), `LicenseKeychainStore` (licenza nel Portachiavi).

## Mappatura in Slash
| Tilde | Slash |
|---|---|
| Split views + tab per pannello | `Workspace` / `Pane` / `FolderTab` (fino a 4 pannelli, ⌘D) |
| Sidebar Spaces + Pinned folders | `Space` in `AppStore`, menu Space nella sidebar |
| Command palette + indice | `CommandPalette.swift` (⌘K, ricerca fuzzy, azioni) |
| Live Groups | `LiveScanner` (file modificati negli ultimi 7 giorni) |
| Properties | `PropertyDefinition` / `selections`, chip nelle righe, menu contestuale |
| Custom folder views | `FolderViewSet` (più viste per cartella: sort, group, filter) |
| Folder nicknames | `nicknames` |
| Image operations | `ImageOps` (flip, ruota, converti PNG/JPEG) |
| Sparkle | `Updater.swift` su GitHub Releases |
| SQLite | singolo `state.json` in `~/Library/Application Support/Slash` |

## Non ancora implementato
Space Overview page, Related items (UI), vista a colonne, Downloads tray, integrazione dialoghi Apri/Salva.
