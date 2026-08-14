import Foundation
import AppKit
import ObjectiveC

/// Optional check / install against public GitHub Releases (no auth, no telemetry).
enum UpdateChecker {
    static let repoOwner = "j0b1t"
    static let repoName = "PinDock"
    static let releasesURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

    struct Result: Equatable {
        let latestVersion: String
        let htmlURL: URL
        let isNewer: Bool
        /// Preferred download: `.zip` of the app, else `.dmg`.
        let downloadURL: URL?
        let downloadIsZip: Bool
    }

    static var localVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var localBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let r = parse(remote)
        let l = parse(local)
        let n = max(r.count, l.count)
        for i in 0..<n {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private static func parse(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    static func checkLatest(completion: @escaping (Result?) -> Void) {
        var request = URLRequest(url: apiURL, timeoutInterval: 12)
        request.setValue("PinDock/\(localVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let tag = (json["tag_name"] as? String) ?? (json["name"] as? String) ?? ""
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            guard !version.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let html: URL
            if let s = json["html_url"] as? String, let u = URL(string: s) {
                html = u
            } else {
                html = releasesURL
            }

            var zipURL: URL?
            var dmgURL: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    let name = (asset["name"] as? String)?.lowercased() ?? ""
                    guard let browser = asset["browser_download_url"] as? String,
                          let url = URL(string: browser) else { continue }
                    if name.hasSuffix(".zip"), name.contains("pindock") || zipURL == nil {
                        if name.hasSuffix(".zip") { zipURL = url }
                    }
                    if name.hasSuffix(".dmg") {
                        dmgURL = url
                        if name.contains("pindock") { /* keep */ }
                    }
                }
            }

            let download = zipURL ?? dmgURL
            let isZip = zipURL != nil

            let newer = isVersion(version, newerThan: localVersion)
            let result = Result(
                latestVersion: version,
                htmlURL: html,
                isNewer: newer,
                downloadURL: download,
                downloadIsZip: isZip
            )
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

// MARK: - Installer

/// Downloads the GitHub release ZIP (or DMG) and replaces `/Applications/PinDock.app`.
enum AppUpdater {
    enum UpdateError: LocalizedError {
        case noAsset
        case downloadFailed
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAsset: return "No download found in the latest release."
            case .downloadFailed: return "Could not download the update."
            case .installFailed(let m): return m
            }
        }
    }

    static func install(
        from url: URL,
        isZip: Bool,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { tempURL, response, error in
            guard error == nil,
                  let tempURL,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async { completion(.failure(UpdateError.downloadFailed)) }
                return
            }

            do {
                let ext = isZip ? "zip" : "dmg"
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PinDock-update-\(UUID().uuidString).\(ext)")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                try runInstallScript(archivePath: dest.path, isZip: isZip)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }

        let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { prog, _ in
            DispatchQueue.main.async { progress(prog.fractionCompleted) }
        }
        objc_setAssociatedObject(task, "obs", observation, .OBJC_ASSOCIATION_RETAIN)
        task.resume()
    }

    private static func runInstallScript(archivePath: String, isZip: Bool) throws {
        let appName = "PinDock"
        let destApp = "/Applications/\(appName).app"
        let currentBundle = Bundle.main.bundlePath

        let installTarget: String
        if currentBundle.hasSuffix(".app"), currentBundle.contains("/Applications/") {
            installTarget = currentBundle
        } else {
            installTarget = destApp
        }

        let extract: String
        if isZip {
            extract = """
            UNZIP_DIR=$(mktemp -d /tmp/pindock-unzip.XXXXXX)
            ditto -x -k \(shellEscape(archivePath)) "$UNZIP_DIR"
            SRC=$(find "$UNZIP_DIR" -maxdepth 3 -name "${APP_NAME}.app" -type d | head -1)
            if [[ -z "$SRC" || ! -d "$SRC" ]]; then
              rm -rf "$UNZIP_DIR"
              echo "app missing in zip" >&2
              exit 1
            fi
            CLEANUP_EXTRA='rm -rf "'"$UNZIP_DIR"'"'
            """
        } else {
            extract = """
            MOUNT_OUT=$(hdiutil attach -nobrowse -readonly \(shellEscape(archivePath)))
            MOUNT=$(echo "$MOUNT_OUT" | sed -n 's|.*\\(/Volumes/.*\\)|\\1|p' | tail -1)
            if [[ -z "$MOUNT" || ! -d "$MOUNT" ]]; then
              echo "mount failed" >&2
              exit 1
            fi
            SRC=$(find "$MOUNT" -maxdepth 2 -name "${APP_NAME}.app" -type d | head -1)
            if [[ -z "$SRC" || ! -d "$SRC" ]]; then
              hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
              echo "app missing on dmg" >&2
              exit 1
            fi
            CLEANUP_EXTRA='hdiutil detach "'"$MOUNT"'" -force >/dev/null 2>&1 || true'
            """
        }

        let script = """
        #!/bin/bash
        set -euo pipefail
        ARCHIVE=\(shellEscape(archivePath))
        DEST=\(shellEscape(installTarget))
        APP_NAME=\(shellEscape(appName))

        for i in $(seq 1 50); do
          if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then break; fi
          sleep 0.2
        done
        sleep 0.3

        \(extract)

        rm -rf "$DEST"
        ditto --norsrc --noextattr "$SRC" "$DEST"
        xattr -cr "$DEST" 2>/dev/null || true
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

        eval "$CLEANUP_EXTRA"
        rm -f "$ARCHIVE"

        open "$DEST"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindock-apply-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApp.terminate(nil)
        }
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
