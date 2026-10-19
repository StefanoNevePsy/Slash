import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Quartz

enum FileOps {
    /// Moves (or copies) files into a folder, keeping Slash metadata attached on move.
    static func move(_ urls: [URL], to folder: URL, copy: Bool, store: AppStore) {
        for src in urls {
            guard src.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL || copy else { continue }
            guard src != folder else { continue }
            let dest = uniqueDestination(for: src.lastPathComponent, in: folder)
            do {
                if copy {
                    try FileManager.default.copyItem(at: src, to: dest)
                } else {
                    try FileManager.default.moveItem(at: src, to: dest)
                    store.moveMetadata(from: src.path, to: dest.path)
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    static func uniqueDestination(for name: String, in folder: URL) -> URL {
        var dest = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return dest
    }
}

enum ImageOps {
    enum Format { case png, jpeg }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    private static func cgImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func transform(_ url: URL, width: Int, height: Int, draw: (CGContext, CGImage) -> Void) {
        guard let img = cgImage(url),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        draw(ctx, img)
        guard let out = ctx.makeImage() else { return }
        let type = UTType(filenameExtension: url.pathExtension) ?? .png
        write(out, to: url, type: type)
    }

    static func flip(_ url: URL, horizontal: Bool) {
        guard let img = cgImage(url) else { return }
        transform(url, width: img.width, height: img.height) { ctx, img in
            if horizontal {
                ctx.translateBy(x: CGFloat(img.width), y: 0); ctx.scaleBy(x: -1, y: 1)
            } else {
                ctx.translateBy(x: 0, y: CGFloat(img.height)); ctx.scaleBy(x: 1, y: -1)
            }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
    }

    static func rotate(_ url: URL) {
        guard let img = cgImage(url) else { return }
        transform(url, width: img.height, height: img.width) { ctx, img in
            ctx.translateBy(x: 0, y: CGFloat(img.width))
            ctx.rotate(by: -.pi / 2)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
    }

    static func convert(_ url: URL, to format: Format) {
        guard let img = cgImage(url) else { return }
        let ext = format == .png ? "png" : "jpg"
        let dest = FileOps.uniqueDestination(
            for: url.deletingPathExtension().lastPathComponent + "." + ext,
            in: url.deletingLastPathComponent()
        )
        write(img, to: dest, type: format == .png ? .png : .jpeg)
    }
}

/// Minimal Quick Look support (space bar / context menu).
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var url: URL?

    static func show(_ url: URL) {
        shared.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}
