import Foundation
import AppKit
import CryptoKit
import ObjectiveC

/// Optional check / install against public GitHub Releases (no auth, no telemetry).
///
/// Hardening:
/// - HTTPS only; download hosts limited to GitHub / githubusercontent
/// - Optional SHA-256 from release notes (required match when present)
/// - Extracted app must be `com.github.pindock.PinDock` and pass `codesign --verify`
/// - Install only into `/Applications/…/PinDock.app`
/// - Does not wipe all xattrs; only clears quarantine after verification
enum UpdateChecker {
    static let repoOwner = "j0b1t"
    static let repoName = "PinDock"
    static let expectedBundleID = "com.github.pindock.PinDock"
    static let releasesURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

    /// Hosts allowed for release API + asset downloads.
    private static let allowedExactHosts: Set<String> = [
        "github.com",
        "www.github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "github-releases.githubusercontent.com",
        "objects-origin.githubusercontent.com",
    ]

    struct Result: Equatable {
        let latestVersion: String
        let htmlURL: URL
        let isNewer: Bool
        /// Preferred download: `.zip` of the app, else `.dmg`.
        let downloadURL: URL?
        let downloadIsZip: Bool
        /// SHA-256 from release body when present (64 hex chars).
        let expectedSHA256: String?
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

    /// True only for HTTPS URLs on GitHub / GitHub user-content hosts.
    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if allowedExactHosts.contains(host) { return true }
        // e.g. `release-assets.githubusercontent.com` variants
        if host.hasSuffix(".githubusercontent.com") { return true }
        return false
    }

    /// Parse `SHA-256` hex from release notes (as written by `Scripts/release.sh`).
    static func parseSHA256(from body: String?, assetHint: String?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        // Prefer line that mentions the asset name, else first 64-hex token near "SHA".
        let hex = #"[A-Fa-f0-9]{64}"#
        if let hint = assetHint?.lowercased(), !hint.isEmpty {
            let lines = body.split(whereSeparator: \.isNewline)
            for line in lines {
                let s = String(line)
                guard s.lowercased().contains(hint) || s.lowercased().contains("pindock") else { continue }
                if let match = s.range(of: hex, options: .regularExpression) {
                    return String(s[match]).lowercased()
                }
            }
        }
        // Fallback: first 64-hex after "SHA"
        if let shaRange = body.range(of: "SHA", options: .caseInsensitive) {
            let tail = String(body[shaRange.lowerBound...])
            if let match = tail.range(of: hex, options: .regularExpression) {
                return String(tail[match]).lowercased()
            }
        }
        if let match = body.range(of: hex, options: .regularExpression) {
            return String(body[match]).lowercased()
        }
        return nil
    }

    static func checkLatest(completion: @escaping (Result?) -> Void) {
        guard isAllowedDownloadURL(apiURL) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

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
            if let s = json["html_url"] as? String,
               let u = URL(string: s),
               isAllowedDownloadURL(u) {
                html = u
            } else {
                html = releasesURL
            }

            let body = json["body"] as? String

            var zipURL: URL?
            var dmgURL: URL?
            var zipName: String?
            var dmgName: String?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    let name = (asset["name"] as? String) ?? ""
                    let nameLower = name.lowercased()
                    guard let browser = asset["browser_download_url"] as? String,
                          let url = URL(string: browser),
                          isAllowedDownloadURL(url) else { continue }
                    // Only PinDock-branded archives
                    guard nameLower.contains("pindock") else { continue }
                    if nameLower.hasSuffix(".zip") {
                        zipURL = url
                        zipName = name
                    } else if nameLower.hasSuffix(".dmg") {
                        dmgURL = url
                        dmgName = name
                    }
                }
            }

            let download = zipURL ?? dmgURL
            let isZip = zipURL != nil
            let assetName = isZip ? zipName : dmgName
            let expectedSHA = parseSHA256(from: body, assetHint: assetName)

            let newer = isVersion(version, newerThan: localVersion)
            let result = Result(
                latestVersion: version,
                htmlURL: html,
                isNewer: newer,
                downloadURL: download,
                downloadIsZip: isZip,
                expectedSHA256: expectedSHA
            )
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

// MARK: - Installer

/// Downloads a verified GitHub release ZIP/DMG and replaces `/Applications/PinDock.app`.
enum AppUpdater {
    enum UpdateError: LocalizedError {
        case noAsset
        case blockedURL
        case downloadFailed
        case hashMismatch
        case verificationFailed(String)
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAsset: return "No download found in the latest release."
            case .blockedURL: return "Download URL is not an allowed GitHub host."
            case .downloadFailed: return "Could not download the update."
            case .hashMismatch: return "Update file hash does not match the release notes (SHA-256)."
            case .verificationFailed(let m): return "Update verification failed: \(m)"
            case .installFailed(let m): return m
            }
        }
    }

    static func install(
        from url: URL,
        isZip: Bool,
        expectedSHA256: String?,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard UpdateChecker.isAllowedDownloadURL(url) else {
            DispatchQueue.main.async { completion(.failure(UpdateError.blockedURL)) }
            return
        }

        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { tempURL, response, error in
            // Move the temp download out immediately — the system may delete it when this handler returns.
            guard error == nil, let tempURL else {
                DispatchQueue.main.async { completion(.failure(UpdateError.downloadFailed)) }
                return
            }
            if let http = response as? HTTPURLResponse {
                guard (200...299).contains(http.statusCode) else {
                    DispatchQueue.main.async { completion(.failure(UpdateError.downloadFailed)) }
                    return
                }
                // Final response URL must still be on the allow-list (redirects).
                if let finalURL = http.url, !UpdateChecker.isAllowedDownloadURL(finalURL) {
                    DispatchQueue.main.async { completion(.failure(UpdateError.blockedURL)) }
                    return
                }
            }

            let workRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("pindock-update-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
                let ext = isZip ? "zip" : "dmg"
                let archive = workRoot.appendingPathComponent("PinDock-update.\(ext)")
                try? FileManager.default.removeItem(at: archive)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: archive)
                } catch {
                    // Cross-volume fallback
                    try FileManager.default.copyItem(at: tempURL, to: archive)
                    try? FileManager.default.removeItem(at: tempURL)
                }

                if let expected = expectedSHA256?.lowercased(), expected.count == 64 {
                    let actual = try sha256Hex(of: archive)
                    guard actual == expected else {
                        NSLog("PinDock: SHA-256 mismatch expected=\(expected) actual=\(actual)")
                        try? FileManager.default.removeItem(at: workRoot)
                        DispatchQueue.main.async { completion(.failure(UpdateError.hashMismatch)) }
                        return
                    }
                    NSLog("PinDock: SHA-256 OK")
                } else {
                    NSLog("PinDock: no SHA-256 in release notes — relying on codesign + bundle ID")
                }

                let extractedApp = try extractAppBundle(from: archive, isZip: isZip, workRoot: workRoot)
                try verifyAppBundle(at: extractedApp)

                let installTarget = try resolvedInstallTarget()
                // IMPORTANT: do NOT delete workRoot here — the async install script still needs SRC.
                // The script removes workRoot after a successful install.
                try runInstallScript(
                    sourceApp: extractedApp.path,
                    installTarget: installTarget,
                    workRoot: workRoot.path
                )

                DispatchQueue.main.async { completion(.success(())) }
            } catch let err as UpdateError {
                try? FileManager.default.removeItem(at: workRoot)
                DispatchQueue.main.async { completion(.failure(err)) }
            } catch {
                try? FileManager.default.removeItem(at: workRoot)
                DispatchQueue.main.async { completion(.failure(UpdateError.installFailed(error.localizedDescription))) }
            }
        }

        let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { prog, _ in
            DispatchQueue.main.async { progress(prog.fractionCompleted) }
        }
        objc_setAssociatedObject(task, "obs", observation, .OBJC_ASSOCIATION_RETAIN)
        task.resume()
    }

    // MARK: - Hash

    private static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Extract

    private static func extractAppBundle(from archive: URL, isZip: Bool, workRoot: URL) throws -> URL {
        if isZip {
            let unzipDir = workRoot.appendingPathComponent("unzip", isDirectory: true)
            try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-x", "-k", archive.path, unzipDir.path]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw UpdateError.verificationFailed("could not unzip archive")
            }
            return try findApp(in: unzipDir, maxDepth: 4)
        } else {
            let attach = Process()
            attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            attach.arguments = ["attach", "-nobrowse", "-readonly", "-plist", archive.path]
            let pipe = Pipe()
            attach.standardOutput = pipe
            attach.standardError = FileHandle.nullDevice
            try attach.run()
            attach.waitUntilExit()
            guard attach.terminationStatus == 0 else {
                throw UpdateError.verificationFailed("could not mount DMG")
            }
            let plistData = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let entities = plist["system-entities"] as? [[String: Any]] else {
                throw UpdateError.verificationFailed("invalid DMG mount info")
            }
            var mountPoint: String?
            for ent in entities {
                if let mp = ent["mount-point"] as? String {
                    mountPoint = mp
                    break
                }
            }
            guard let mountPoint, !mountPoint.isEmpty else {
                throw UpdateError.verificationFailed("DMG has no mount point")
            }
            defer {
                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountPoint, "-force"]
                detach.standardOutput = FileHandle.nullDevice
                detach.standardError = FileHandle.nullDevice
                try? detach.run()
                detach.waitUntilExit()
            }
            let appOnVolume = try findApp(in: URL(fileURLWithPath: mountPoint), maxDepth: 3)
            // Copy off the volume so we can detach and still verify/install.
            let copyDest = workRoot.appendingPathComponent("PinDock.app", isDirectory: true)
            try? FileManager.default.removeItem(at: copyDest)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["--norsrc", "--noextattr", appOnVolume.path, copyDest.path]
            ditto.standardOutput = FileHandle.nullDevice
            ditto.standardError = FileHandle.nullDevice
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else {
                throw UpdateError.verificationFailed("could not copy app from DMG")
            }
            return copyDest
        }
    }

    private static func findApp(in root: URL, maxDepth: Int) throws -> URL {
        var found: URL?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw UpdateError.verificationFailed("could not scan archive")
        }
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "app", url.lastPathComponent == "PinDock.app" {
                found = url
                break
            }
        }
        guard let found else {
            throw UpdateError.verificationFailed("PinDock.app missing in archive")
        }
        return found
    }

    // MARK: - Verify

    private static func verifyAppBundle(at appURL: URL) throws {
        // Bundle ID
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let bid = plist["CFBundleIdentifier"] as? String else {
            throw UpdateError.verificationFailed("missing Info.plist")
        }
        guard bid == UpdateChecker.expectedBundleID else {
            throw UpdateError.verificationFailed("bundle id is \(bid), expected \(UpdateChecker.expectedBundleID)")
        }

        // Executable path exists
        let execName = (plist["CFBundleExecutable"] as? String) ?? "PinDock"
        let execURL = appURL.appendingPathComponent("Contents/MacOS/\(execName)")
        guard FileManager.default.isExecutableFile(atPath: execURL.path) else {
            throw UpdateError.verificationFailed("missing executable")
        }

        // codesign --verify (integrity of signature blob)
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--verbose=2", appURL.path]
        let errPipe = Pipe()
        verify.standardOutput = FileHandle.nullDevice
        verify.standardError = errPipe
        try verify.run()
        verify.waitUntilExit()
        if verify.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError.verificationFailed("codesign verify failed\(err.isEmpty ? "" : ": \(err.trimmingCharacters(in: .whitespacesAndNewlines))")")
        }

        // Identifier inside the signature should match (when present)
        let display = Process()
        display.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        display.arguments = ["-d", "--verbose=2", appURL.path]
        let dispPipe = Pipe()
        display.standardOutput = FileHandle.nullDevice
        display.standardError = dispPipe // codesign -d writes to stderr
        try display.run()
        display.waitUntilExit()
        let info = String(data: dispPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if let idLine = info.split(separator: "\n").first(where: { $0.hasPrefix("Identifier=") }) {
            let id = idLine.dropFirst("Identifier=".count)
            if id != UpdateChecker.expectedBundleID {
                throw UpdateError.verificationFailed("codesign identifier is \(id)")
            }
        }

        // If the running app is signed, prefer the same TeamIdentifier when both are set.
        if let runningTeam = codesignTeamID(for: Bundle.main.bundlePath),
           let updateTeam = codesignTeamID(for: appURL.path),
           !runningTeam.isEmpty, !updateTeam.isEmpty,
           runningTeam != "not set", updateTeam != "not set",
           runningTeam != updateTeam {
            throw UpdateError.verificationFailed("Team ID mismatch (\(updateTeam) vs \(runningTeam))")
        }

        NSLog("PinDock: update bundle verified id=\(bid) path=\(appURL.path)")
    }

    private static func codesignTeamID(for path: String) -> String? {
        let display = Process()
        display.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        display.arguments = ["-d", "--verbose=2", path]
        let pipe = Pipe()
        display.standardOutput = FileHandle.nullDevice
        display.standardError = pipe
        do {
            try display.run()
            display.waitUntilExit()
        } catch {
            return nil
        }
        let info = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in info.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                return String(line.dropFirst("TeamIdentifier=".count))
            }
        }
        return nil
    }

    // MARK: - Install target

    /// Only allow replacing PinDock under `/Applications`.
    private static func resolvedInstallTarget() throws -> String {
        let destApp = "/Applications/PinDock.app"
        let current = Bundle.main.bundlePath
        let target: String
        if current.hasSuffix("/PinDock.app"),
           current.hasPrefix("/Applications/") {
            target = current
        } else {
            target = destApp
        }
        // Path hardening: no traversal, must end with PinDock.app, under Applications.
        let standardized = (target as NSString).standardizingPath
        guard standardized.hasPrefix("/Applications/"),
              standardized.hasSuffix("/PinDock.app") || standardized == "/Applications/PinDock.app",
              !standardized.contains("..") else {
            throw UpdateError.installFailed("refusing to install outside /Applications/PinDock.app")
        }
        return standardized
    }

    // MARK: - Apply

    /// Async helper: wait for PinDock to quit, replace app, clear quarantine only, reopen.
    /// Keeps `workRoot` until after install so SRC is not deleted early (previous bug).
    private static func runInstallScript(sourceApp: String, installTarget: String, workRoot: String) throws {
        let logPath = "/tmp/pindock-update.log"
        let script = """
        #!/bin/bash
        set -euo pipefail
        SRC=\(shellEscape(sourceApp))
        DEST=\(shellEscape(installTarget))
        WORK=\(shellEscape(workRoot))
        APP_NAME='PinDock'
        LOG=\(shellEscape(logPath))
        exec >>"$LOG" 2>&1
        echo "==== $(date) apply update ===="
        echo "SRC=$SRC"
        echo "DEST=$DEST"
        echo "WORK=$WORK"

        # Wait for the running app to exit (we terminate after launching this script).
        for i in $(seq 1 80); do
          if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            echo "PinDock not running (waited ${i} ticks)"
            break
          fi
          sleep 0.25
        done
        sleep 0.5

        if [[ ! -d "$SRC" ]]; then
          echo "ERROR: source app missing: $SRC"
          exit 1
        fi

        # Destination must stay under /Applications
        case "$DEST" in
          /Applications/*PinDock.app) ;;
          *) echo "ERROR: invalid dest $DEST"; exit 1 ;;
        esac

        # Stage to a sibling path first, then swap — avoids a half-deleted app if we crash mid-copy.
        STAGE="$(dirname "$DEST")/.PinDock-update-staging.app"
        rm -rf "$STAGE"
        /usr/bin/ditto --norsrc --noextattr "$SRC" "$STAGE"
        /usr/bin/codesign --verify "$STAGE" || { echo "ERROR: staged codesign failed"; rm -rf "$STAGE"; exit 1; }

        rm -rf "$DEST"
        mv "$STAGE" "$DEST"

        # Quarantine only (do not wipe all extended attributes)
        /usr/bin/xattr -d com.apple.quarantine "$DEST" 2>/dev/null || true
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

        /usr/bin/codesign --verify "$DEST" || { echo "ERROR: post-install codesign failed"; exit 1; }

        echo "install OK → opening"
        /usr/bin/open "$DEST"

        # Safe to remove extract/download tree now
        rm -rf "$WORK"
        echo "done"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindock-apply-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Detach from this process group so quitting PinDock does not kill the installer.
        // Outer shell backgrounds the helper and exits immediately.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [
            "-c",
            "(/bin/bash \(shellEscape(scriptURL.path))) >/dev/null 2>&1 &",
        ]
        try launcher.run()
        launcher.waitUntilExit()

        NSLog("PinDock: install helper launched (log \(logPath)); quitting for replace")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
