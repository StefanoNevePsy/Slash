import SwiftUI
import AppKit

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Shows the custom icon chosen for a folder, or the normal Finder icon.
struct FolderIconView: View {
    @Environment(AppStore.self) private var store
    let url: URL
    let isDirectory: Bool
    var size: CGFloat = 18

    var body: some View {
        if let icon = store.icon(for: url.path) {
            Image(systemName: icon.symbol)
                .font(.system(size: size * 0.8))
                .foregroundStyle(icon.color.color)
                .frame(width: size, height: size)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

/// Grid of SF Symbols grouped by theme, with search, color and "type any symbol name".
struct IconPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let path: String

    @State private var search = ""
    @State private var color: PropertyColor = .blue
    @State private var selected: String?

    private static let catalog: [(String, [String])] = [
        ("Cartelle", ["folder.fill", "folder.badge.person.crop", "folder.badge.gearshape", "archivebox.fill", "tray.full.fill",
                      "shippingbox.fill", "externaldrive.fill", "icloud.fill", "server.rack", "square.stack.3d.up.fill"]),
        ("Lavoro", ["briefcase.fill", "doc.text.fill", "doc.richtext.fill", "list.clipboard.fill", "clipboard.fill",
                    "signature", "calendar", "chart.bar.fill", "chart.pie.fill", "building.2.fill", "banknote.fill", "creditcard.fill",
                    "eurosign.circle.fill", "receipt.fill", "envelope.fill", "paperplane.fill", "phone.fill", "video.fill"]),
        ("Persone e cura", ["person.fill", "person.2.fill", "person.3.fill", "figure.and.child.holdinghands", "figure.2.and.child.holdinghands",
                            "figure.child", "figure.walk", "figure.mind.and.body", "brain.head.profile", "brain", "heart.fill",
                            "heart.text.square.fill", "cross.case.fill", "stethoscope", "pills.fill", "hand.raised.fill",
                            "bubble.left.and.bubble.right.fill", "ear.fill", "eye.fill", "puzzlepiece.fill", "house.fill"]),
        ("Studio", ["book.fill", "books.vertical.fill", "graduationcap.fill", "pencil", "highlighter", "bookmark.fill",
                    "text.book.closed.fill", "magazine.fill", "newspaper.fill", "lightbulb.fill", "testtube.2", "studentdesk"]),
        ("Media", ["photo.fill", "photo.on.rectangle.angled", "camera.fill", "film.fill", "music.note", "waveform", "mic.fill",
                   "paintpalette.fill", "paintbrush.fill", "scribble", "pencil.and.ruler.fill", "theatermasks.fill"]),
        ("Sviluppo", ["chevron.left.forwardslash.chevron.right", "terminal.fill", "hammer.fill", "wrench.and.screwdriver.fill",
                      "gearshape.fill", "cpu.fill", "laptopcomputer", "desktopcomputer", "iphone", "globe", "network", "ladybug.fill"]),
        ("Simboli", ["star.fill", "flag.fill", "tag.fill", "pin.fill", "bolt.fill", "flame.fill", "leaf.fill", "sun.max.fill",
                     "moon.fill", "cloud.fill", "snowflake", "drop.fill", "sparkles", "checkmark.seal.fill", "exclamationmark.triangle.fill",
                     "lock.fill", "key.fill", "bell.fill", "gift.fill", "cart.fill", "airplane", "car.fill", "map.fill", "pawprint.fill"])
    ]

    /// Only symbols present on this macOS version.
    private static func available(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private var sections: [(String, [String])] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        var out = Self.catalog.map { title, names in
            (title, names.filter { Self.available($0) && (q.isEmpty || $0.contains(q)) })
        }.filter { !$0.1.isEmpty }
        // Any exact SF Symbol name typed by the user (see the SF Symbols app for names)
        if !q.isEmpty, Self.available(q), !out.contains(where: { $0.1.contains(q) }) {
            out.insert(("Nome digitato", [q]), at: 0)
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Icona per “\(store.displayName(for: URL(fileURLWithPath: path)))”").font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top], 16)

            TextField("Cerca (in inglese, es. heart, book, person) o nome SF Symbol", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            HStack(spacing: 8) {
                ForEach(PropertyColor.allCases, id: \.self) { c in
                    Circle()
                        .fill(c.color)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.primary, lineWidth: c == color ? 2 : 0).padding(-3))
                        .onTapGesture { color = c }
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sections, id: \.0) { title, names in
                        Text(title).font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 10), spacing: 6) {
                            ForEach(names, id: \.self) { name in
                                Image(systemName: name)
                                    .font(.system(size: 18))
                                    .foregroundStyle(color.color)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(name == selected ? color.color.opacity(0.2) : Color.primary.opacity(0.05))
                                    )
                                    .help(name)
                                    .onTapGesture(count: 2) { selected = name; save() }
                                    .onTapGesture { selected = name }
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()
            HStack {
                if store.icon(for: path) != nil {
                    Button("Ripristina icona originale") {
                        store.setIcon(nil, for: path)
                        dismiss()
                    }
                }
                Spacer()
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Usa icona") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
            .padding(16)
        }
        .frame(width: 500, height: 560)
        .onAppear {
            if let current = store.icon(for: path) {
                selected = current.symbol
                color = current.color
            }
        }
    }

    private func save() {
        guard let selected else { return }
        store.setIcon(FolderIcon(symbol: selected, color: color), for: path)
        dismiss()
    }
}
