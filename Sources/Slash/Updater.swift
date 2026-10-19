import Foundation
import AppKit

/// Self-updater backed by GitHub Releases.
/// Checks the latest release of the repo, and if its tag (e.g. "v1.2.0") is newer than
/// the running version, downloads the `Slash.zip` asset, swaps the app bundle and relaunches.
final class Updater {
    static let shared = Updater()
    static let repo = "StefanoNevePsy/Slash"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private struct Release: Decodable {
        let tag_name: String
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
    }

    private var isChecking = false

    /// Called at launch and then every 6 hours, if enabled in Settings.
    func checkInBackground() {
        let enabled = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
        if enabled { Task { await check(interactive: false) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6 * 3600) { [weak self] in self?.checkInBackground() }
    }

    func checkNow() {
        Task { await check(interactive: true) }
    }

    @MainActor
    private func check(interactive: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            guard Self.isNewer(latest, than: Self.currentVersion),
                  let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
                if interactive { info("You're up to date", "Slash \(Self.currentVersion) is the latest version.") }
                return
            }

            let alert = NSAlert()
            alert.messageText = "Slash \(latest) is available"
            alert.informativeText = "You have \(Self.currentVersion).\n\n\(release.body ?? "")"
            alert.addButton(withTitle: "Install and Relaunch")
            alert.addButton(withTitle: "Later")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            try await install(from: asset.browser_download_url)
        } catch {
            if interactive { info("Update check failed", error.localizedDescription) }
        }
    }

    @MainActor
    private func install(from url: URL) async throws {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            info("Can't update", "Slash isn't running from an .app bundle (development build).")
            return
        }

        let (zip, _) = try await URLSession.shared.download(from: url)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SlashUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

        guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "Slash", code: 1, userInfo: [NSLocalizedDescriptionKey: "The update archive has no app inside."])
        }

        // A tiny script waits for us to quit, swaps the bundle and reopens it.
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(bundleURL.path)"
        mv "\(newApp.path)" "\(bundleURL.path)"
        xattr -dr com.apple.quarantine "\(bundleURL.path)" 2>/dev/null
        open "\(bundleURL.path)"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try p.run()
        await MainActor.run { NSApp.terminate(nil) }
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "Slash", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) failed while unpacking the update."])
        }
    }

    @MainActor
    private func info(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    /// Compares dotted versions numerically: "1.10.0" > "1.9.3".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
