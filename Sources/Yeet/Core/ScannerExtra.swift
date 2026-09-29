import Foundation

/// Additional cache sources. Every item here is either "Safe" (recreated automatically)
/// or "Re-download" (re-downloaded / rebuilt on next use). Nothing that can't be recreated
/// (backups, archives, history, virtualenvs, emulators, Docker disks…) is ever listed.
extension Scanner {

    // MARK: - Helpers

    private static func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    /// Adds a leaf only when the path exists and is non-empty (keeps optional tools out of the way).
    private static func optionalLeaf(_ id: String, _ name: String, _ u: URL, _ tool: ToolKind,
                                     risk: Risk, note: String, action: CleanAction,
                                     minSize: Int64 = 1) -> CacheNode? {
        guard exists(u) else { return nil }
        let s = stats(u)
        guard s.size >= minSize else { return nil }
        return leaf(id, name, u, tool, risk: risk, note: note, action: action, stats: s)
    }

    private static func quit(_ action: CleanAction, _ bundleID: String) -> CleanAction {
        var a = action
        a.requiresQuitBundleID = bundleID
        return a
    }

    /// Project folders (from Settings) containing `marker`, with an `artifact` folder next to it.
    static func findProjectArtifacts(roots: [URL], marker: String, artifact: String,
                                     validate: (URL) -> Bool = { _ in true }, maxDepth: Int = 5) -> [URL] {
        let fm = FileManager.default
        let skip: Set<String> = ["node_modules", "target", "Pods", "DerivedData", "build", "Build", ".build",
                                 "vendor", "Carthage", "Library", "dist", ".next", ".gradle"]
        var found: [URL] = []
        var seen = Set<String>()
        for root in roots {
            var queue: [(URL, Int)] = [(root, 0)]
            var index = 0
            while index < queue.count {
                let (dir, depth) = queue[index]
                index += 1
                let art = dir.appendingPathComponent(artifact, isDirectory: true)
                if fm.fileExists(atPath: dir.appendingPathComponent(marker).path),
                   fm.fileExists(atPath: art.path), validate(art),
                   seen.insert(art.path).inserted {
                    found.append(art)
                }
                guard depth < maxDepth else { continue }
                for c in subdirs(dir) where !skip.contains(c.lastPathComponent) && c.pathExtension != "app" {
                    queue.append((c, depth + 1))
                }
            }
        }
        return found
    }

    private static func dirModified(_ u: URL) -> Date? {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: - Xcode: simulator runtimes (direct build only)

    /// Old simulator runtimes via `xcrun simctl runtime list -j`. Only runs when a full Xcode
    /// is selected (calling xcrun without Xcode would pop up the CLT installer).
    static func simulatorRuntimes() -> [CacheNode] {
        guard let dev = Shell.capture("/usr/bin/xcode-select", ["-p"]),
              dev.contains(".app/Contents/Developer"),
              let json = Shell.capture("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        struct RT { let id, platform, version, build: String; let size: Int64; let path: String; let used: Date? }
        let iso = ISO8601DateFormatter()
        var list: [RT] = []
        for (_, value) in dict {
            guard let r = value as? [String: Any],
                  (r["deletable"] as? Bool) ?? false,
                  let id = r["identifier"] as? String,
                  let version = r["version"] as? String else { continue }
            let pid = (r["platformIdentifier"] as? String) ?? ""
            let platform: String
            if pid.contains("iphone") { platform = "iOS" }
            else if pid.contains("watch") { platform = "watchOS" }
            else if pid.contains("appletv") { platform = "tvOS" }
            else if pid.contains("xr") { platform = "visionOS" }
            else { platform = "Simulator" }
            let size = (r["sizeBytes"] as? NSNumber)?.int64Value ?? 0
            let path = (r["path"] as? String) ?? (r["mountPath"] as? String) ?? "/Library/Developer/CoreSimulator"
            let used = (r["lastUsedAt"] as? String).flatMap { iso.date(from: $0) }
            list.append(RT(id: id, platform: platform, version: version, build: (r["build"] as? String) ?? "",
                           size: size, path: path, used: used))
        }
        func ver(_ v: String) -> [Int] { v.split(separator: ".").compactMap { Int($0) } }
        var newest: [String: [Int]] = [:]
        for r in list where (newest[r.platform].map { ver(r.version).lexicographicallyPrecedes($0) == false } ?? true) {
            newest[r.platform] = ver(r.version)
        }
        return list
            .sorted { $0.platform == $1.platform ? ver($1.version).lexicographicallyPrecedes(ver($0.version)) : $0.platform < $1.platform }
            .map { r in
                let older = ver(r.version).lexicographicallyPrecedes(newest[r.platform] ?? [])
                return CacheNode(
                    id: "xcode.runtime.\(r.id)", name: "\(r.platform) \(r.version) (\(r.build))",
                    url: URL(fileURLWithPath: r.path), tool: .xcode,
                    leafSize: r.size, fileCount: 1, modified: r.used,
                    risk: older ? .safe : .rebuild,
                    note: older
                        ? L("Older than the newest \(r.platform) runtime on this Mac. Only needed if you still test on \(r.platform) \(r.version); you can re-download it in Xcode → Settings → Components.",
                            "Runtime \(r.platform) cũ hơn bản mới nhất trên máy. Chỉ cần nếu bạn còn test trên \(r.platform) \(r.version); tải lại được trong Xcode → Settings → Components.")
                        : L("Newest \(r.platform) runtime. If deleted, you'll have to re-download it (~7 GB) in Xcode → Settings → Components before simulators can run.",
                            "Runtime \(r.platform) mới nhất. Xoá thì phải tải lại (~7 GB) trong Xcode → Settings → Components mới chạy được simulator."),
                    action: CleanAction(command: "xcrun simctl runtime delete \(r.id)",
                                        display: "xcrun simctl runtime delete \(r.id)"))
            }
    }

    // MARK: - CocoaPods, SwiftPM, Carthage

    static func swiftDeps() -> [CacheNode] {
        let t = ToolKind.swiftDeps
        let pods = Paths.url("Library/Caches/CocoaPods")
        let spm = Paths.url("Library/Caches/org.swift.swiftpm")
        let carthage = Paths.url("Library/Caches/org.carthage.CarthageKit")
        return [
            leaf("swift.pods", "CocoaPods cache", pods, t, risk: .rebuild,
                 note: L("Downloaded pods. The next pod install re-downloads them. The Pods/ folder in your projects is not affected.",
                       "Pod đã tải. Lần pod install kế tiếp sẽ tải lại. Thư mục Pods/ trong dự án không bị ảnh hưởng."),
                 action: toolAction("pod cache clean --all", display: "pod cache clean --all", remove: pods)),
            leaf("swift.spm", "Swift Package Manager cache", spm, t, risk: .rebuild,
                 note: L("SwiftPM repository clones and manifest cache. The next package resolve re-downloads them. Configuration (mirrors, registries) is left untouched.",
                       "Bản clone repository và manifest cache của SwiftPM. Lần resolve package kế tiếp sẽ tải lại. Cấu hình (mirror, registry) không bị đụng tới."),
                 action: rm(spm)),
            leaf("swift.carthage", "Carthage cache", carthage, t, risk: .rebuild,
                 note: L("Carthage downloads and build cache. carthage bootstrap re-downloads them.",
                       "Bản tải và build cache của Carthage. carthage bootstrap sẽ tải lại."), action: rm(carthage)),
        ]
    }

    // MARK: - pnpm & Bun

    static func pnpmBun() -> [CacheNode] {
        let t = ToolKind.pnpm
        let store = Paths.url("Library/pnpm/store")
        let meta = Paths.url("Library/Caches/pnpm")
        let bun = Paths.url(".bun/install/cache")
        return [
            leaf("pnpm.store", "pnpm store", store, t, risk: .rebuild,
                 note: L("pnpm's shared package store. Existing node_modules keep working (hard links); the next pnpm install re-downloads packages.",
                       "Kho package dùng chung của pnpm. node_modules hiện có vẫn chạy (hard link); lần pnpm install kế tiếp sẽ tải lại."),
                 action: rmContents(store)),
            leaf("pnpm.meta", "pnpm metadata cache", meta, t, risk: .safe,
                 note: L("Registry metadata cached by pnpm. Re-downloaded when needed.",
                       "Metadata registry do pnpm cache. Tự tải lại khi cần."), action: rm(meta)),
            leaf("bun.cache", "Bun install cache", bun, t, risk: .rebuild,
                 note: L("Packages downloaded by bun install. The next install re-downloads them.",
                       "Package đã tải của bun install. Lần cài kế tiếp sẽ tải lại."),
                 action: toolAction("bun pm cache rm", display: "bun pm cache rm", remove: bun, contentsOnly: true)),
        ]
    }

    // MARK: - node_modules in projects

    static func nodeModules(roots: [URL]) -> [CacheNode] {
        let t = ToolKind.nodeModules
        return findProjectArtifacts(roots: roots, marker: "package.json", artifact: "node_modules")
            .map { nm -> CacheNode in
                let project = nm.deletingLastPathComponent()
                var s = stats(nm)
                // npm stamps package files with a fixed 1985 mtime, so use the folder / manifest dates instead.
                let touched = [dirModified(nm), dirModified(project.appendingPathComponent("package.json")),
                               dirModified(nm.appendingPathComponent(".package-lock.json"))].compactMap { $0 }.max()
                s.modified = touched
                let stale = touched.map { Date().timeIntervalSince($0) > 30 * 86_400 } ?? true
                return leaf("nm.\(nm.path)", project.lastPathComponent, nm, t, risk: stale ? .safe : .rebuild,
                            note: stale
                                ? L("Packages haven't been reinstalled in over 30 days. Run npm/yarn/pnpm install when you resume work.",
                                    "Dự án không cài lại package hơn 30 ngày. Chạy npm/yarn/pnpm install khi cần làm tiếp.")
                                : L("Project used recently. You'll need to run npm/yarn/pnpm install again before building.",
                                    "Dự án đang dùng gần đây. Phải chạy lại npm/yarn/pnpm install trước khi build."),
                            action: rm(nm), stats: s)
            }
            .filter { $0.leafSize > 0 }
            .sorted { $0.leafSize > $1.leafSize }
    }

    // MARK: - Python

    static func python() -> [CacheNode] {
        let t = ToolKind.python
        var out: [CacheNode] = []
        let pip = Paths.url("Library/Caches/pip")
        out.append(leaf("py.pip", "pip cache", pip, t, risk: .rebuild,
                        note: L("pip wheels and downloads. pip install re-downloads them.",
                        "Wheel và bản tải của pip. pip install sẽ tải lại."), action: rm(pip)))
        // Poetry: only download caches – never ~/Library/Caches/pypoetry/virtualenvs.
        for sub in ["cache", "artifacts"] {
            let u = Paths.url("Library/Caches/pypoetry/\(sub)")
            out.append(leaf("py.poetry.\(sub)", "Poetry \(sub)", u, t, risk: .rebuild,
                            note: L("Poetry downloads. Poetry virtualenvs are left untouched.",
                            "Bản tải của Poetry. Virtualenv của Poetry không bị đụng tới."), action: rm(u)))
        }
        let uv = Paths.url(".cache/uv")
        out.append(leaf("py.uv", "uv cache", uv, t, risk: .rebuild,
                        note: L("uv package cache. Existing .venv environments keep working.",
                        "Cache package của uv. Môi trường .venv hiện có vẫn chạy."),
                        action: toolAction("uv cache clean", display: "uv cache clean", remove: uv)))
        #if !APPSTORE
        // Conda package caches. Only `conda clean` itself knows which packages environments still
        // link to, so it is never replaced by a direct delete (and is skipped in the sandbox).
        for base in ["miniconda3", "anaconda3", "miniforge3", "mambaforge", "opt/miniconda3", "opt/anaconda3"] {
            let pkgs = Paths.url("\(base)/pkgs")
            let conda = Paths.url("\(base)/bin/conda")
            guard FileManager.default.isExecutableFile(atPath: conda.path) else { continue }
            if let n = optionalLeaf("py.conda.\(base)", "Conda pkgs (\(base))", pkgs, t, risk: .rebuild,
                                    note: L("Downloaded Conda packages. conda clean only removes packages no environment still uses.",
                                            "Gói Conda đã tải. conda clean chỉ xoá gói mà các môi trường không còn dùng."),
                                    action: CleanAction(command: "\(Paths.shellQuote(conda.path)) clean --all --yes",
                                                        display: "conda clean --all --yes"),
                                    minSize: 1_000_000) {
                out.append(n)
            }
        }
        #endif
        return out
    }

    // MARK: - Go

    static func golang() -> [CacheNode] {
        let t = ToolKind.go
        let build = Paths.url("Library/Caches/go-build")
        let mod = Paths.url("go/pkg/mod")
        return [
            leaf("go.build", "Go build cache", build, t, risk: .safe,
                 note: L("Cached compilation results. The next build will be a little slower.",
                       "Kết quả biên dịch được cache. Build kế tiếp chậm hơn một chút."),
                 action: toolAction("go clean -cache", display: "go clean -cache", remove: build)),
            leaf("go.mod", "Go module cache", mod, t, risk: .rebuild,
                 note: L("Downloaded modules (go mod download). The next build re-downloads them.",
                       "Module đã tải (go mod download). Lần build kế tiếp sẽ tải lại."),
                 action: toolAction("go clean -modcache", display: "go clean -modcache", remove: mod)),
        ]
    }

    // MARK: - Rust

    static func rust(roots: [URL]) -> [CacheNode] {
        let t = ToolKind.rust
        var out: [CacheNode] = []
        let regCache = Paths.url(".cargo/registry/cache")
        let regSrc = Paths.url(".cargo/registry/src")
        let gitCo = Paths.url(".cargo/git/checkouts")
        out.append(leaf("rust.regcache", "Registry cache (.crate)", regCache, t, risk: .rebuild,
                        note: L("Downloaded .crate files. cargo re-downloads them on build.",
                        "File .crate đã tải. cargo sẽ tải lại khi build."), action: rmContents(regCache)))
        out.append(leaf("rust.regsrc", "Registry source", regSrc, t, risk: .safe,
                        note: L("Extracted crate sources. cargo re-extracts them from the cache.",
                        "Mã nguồn crate đã giải nén. cargo tự giải nén lại từ cache."), action: rmContents(regSrc)))
        out.append(leaf("rust.git", "Git checkouts", gitCo, t, risk: .rebuild,
                        note: L("Dependencies fetched from git. cargo checks them out again.",
                        "Dependency lấy từ git. cargo sẽ checkout lại."), action: rmContents(gitCo)))

        let targets = findProjectArtifacts(roots: roots, marker: "Cargo.toml", artifact: "target", validate: { u in
            // Only folders Cargo created (it writes CACHEDIR.TAG / .rustc_info.json).
            exists(u.appendingPathComponent("CACHEDIR.TAG")) || exists(u.appendingPathComponent(".rustc_info.json"))
        })
        let rows = targets.map { u -> CacheNode in
            let project = u.deletingLastPathComponent()
            return leaf("rust.target.\(u.path)", project.lastPathComponent, u, t, risk: .rebuild,
                        note: L("Project build output. cargo build recompiles from scratch.",
                          "Build output của dự án. cargo build sẽ biên dịch lại từ đầu."),
                        action: toolAction("cargo clean --manifest-path \(Paths.shellQuote(project.appendingPathComponent("Cargo.toml").path))",
                                           display: "cargo clean  # \(Paths.tilde(project))", remove: u))
        }
        .filter { $0.leafSize > 0 }
        .sorted { $0.leafSize > $1.leafSize }
        if !rows.isEmpty {
            out.append(group("rust.targets", L("Project target/ folders", "Thư mục target/ của dự án"), roots.first ?? Paths.home, t,
                             path: L("target/ in project folders", "target/ trong thư mục dự án"), children: rows))
        }
        return out
    }

    // MARK: - Maven

    static func maven() -> [CacheNode] {
        let t = ToolKind.maven
        let repo = Paths.url(".m2/repository")
        let wrapper = Paths.url(".m2/wrapper/dists")
        return [
            leaf("maven.repo", "Local repository", repo, t, risk: .rebuild,
                 note: L("Downloaded Maven dependencies. mvn re-downloads them on the next build. settings.xml is left untouched.",
                       "Dependency Maven đã tải. mvn sẽ tải lại ở lần build kế tiếp. settings.xml không bị đụng tới."),
                 action: rmContents(repo)),
            leaf("maven.wrapper", "Maven wrapper dists", wrapper, t, risk: .rebuild,
                 note: L("Maven distributions downloaded by ./mvnw. Re-downloaded when you run mvnw.",
                       "Các bản Maven do ./mvnw tải. Sẽ tải lại khi chạy mvnw."), action: rmContents(wrapper)),
        ]
    }

    // MARK: - Flutter & Dart

    static func flutter() -> [CacheNode] {
        let t = ToolKind.flutter
        let pub = Paths.url(".pub-cache/hosted")
        let pubGit = Paths.url(".pub-cache/git")
        return [
            leaf("flutter.pub", "Pub cache (hosted)", pub, t, risk: .rebuild,
                 note: L("Downloaded pub.dev packages. flutter pub get re-downloads them. Tools installed with dart pub global are left untouched.",
                       "Package pub.dev đã tải. flutter pub get sẽ tải lại. Công cụ cài bằng dart pub global không bị đụng tới."),
                 action: rmContents(pub)),
            leaf("flutter.git", "Pub cache (git)", pubGit, t, risk: .rebuild,
                 note: L("Packages fetched from git. flutter pub get re-downloads them.",
                       "Package lấy từ git. flutter pub get sẽ tải lại."), action: rmContents(pubGit)),
        ]
    }

    // MARK: - Homebrew

    static func homebrew() -> [CacheNode] {
        let t = ToolKind.homebrew
        let cache = Paths.url("Library/Caches/Homebrew")
        let logs = Paths.url("Library/Logs/Homebrew")
        return [
            leaf("brew.cache", L("Downloads", "Bản tải xuống"), cache, t, risk: .safe,
                 note: L("Homebrew bottles and downloads. Installed packages are not affected.",
                       "Bottle và bản tải của Homebrew. Gói đã cài không bị ảnh hưởng."),
                 action: toolAction("brew cleanup --prune=all -s", display: "brew cleanup --prune=all -s",
                                    remove: cache, contentsOnly: true)),
            leaf("brew.logs", L("Logs", "Log"), logs, t, risk: .safe,
                 note: L("Homebrew build/install logs.", "Log build/cài đặt của Homebrew."), action: rmContents(logs)),
        ]
    }

    // MARK: - IDE & Editor

    static func ides() -> [CacheNode] {
        let t = ToolKind.ide
        var out: [CacheNode] = []
        let editors: [(String, String, String)] = [
            ("VS Code", "Code", "com.microsoft.VSCode"),
            ("Cursor", "Cursor", "com.todesktop.230313mzl4w4u92"),
            ("Windsurf", "Windsurf", "com.exafunction.windsurf"),
        ]
        for (name, folder, bundle) in editors {
            let base = Paths.url("Library/Application Support/\(folder)")
            guard exists(base) else { continue }
            var rows: [CacheNode] = []
            for sub in ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache", "logs"] {
                let u = base.appendingPathComponent(sub, isDirectory: true)
                if let n = optionalLeaf("ide.\(folder).\(sub)", sub, u, t, risk: .safe,
                                        note: L("\(name) caches/logs, recreated on launch. Settings and extensions are not affected. Quit \(name) before deleting.",
                                                "Cache/log của \(name), tự tạo lại khi mở. Cài đặt và extension không bị ảnh hưởng. Thoát \(name) trước khi xoá."),
                                        action: quit(rm(u), bundle)) {
                    rows.append(n)
                }
            }
            if !rows.isEmpty {
                out.append(group("ide.\(folder)", name, base, t, children: rows.sorted { $0.leafSize > $1.leafSize }))
            }
        }

        // JetBrains: caches of *older* IDE versions only (the current version may be running).
        let jbCaches = Paths.url("Library/Caches/JetBrains")
        let dirs = subdirs(jbCaches)
        func split(_ name: String) -> (String, [Int]) {
            let product = String(name.prefix { !$0.isNumber })
            let version = name.dropFirst(product.count).split(separator: ".").compactMap { Int($0) }
            return (product, version)
        }
        var newest: [String: [Int]] = [:]
        for d in dirs {
            let (p, v) = split(d.lastPathComponent)
            if newest[p].map({ $0.lexicographicallyPrecedes(v) }) ?? true { newest[p] = v }
        }
        let old = dirs.filter {
            let (p, v) = split($0.lastPathComponent)
            return !v.isEmpty && v.lexicographicallyPrecedes(newest[p] ?? [])
        }
        let jbRows = old.compactMap { u in
            optionalLeaf("ide.jb.\(u.lastPathComponent)", u.lastPathComponent, u, t, risk: .safe,
                         note: L("Caches (indexes, logs) of an older JetBrains version that has been replaced by a newer one.",
                                 "Cache (index, log) của phiên bản JetBrains cũ đã được thay bằng bản mới hơn."), action: rm(u))
        }
        let jbLogs = Paths.url("Library/Logs/JetBrains")
        var jbChildren = jbRows
        if let logs = optionalLeaf("ide.jb.logs", L("JetBrains logs", "Log JetBrains"), jbLogs, t, risk: .safe,
                                   note: L("Logs from JetBrains IDEs.", "Log của các IDE JetBrains."), action: rmContents(jbLogs)) {
            jbChildren.append(logs)
        }
        if !jbChildren.isEmpty {
            out.append(group("ide.jetbrains", "JetBrains", jbCaches, t, children: jbChildren.sorted { $0.leafSize > $1.leafSize }))
        }
        return out
    }

    // MARK: - App caches

    /// ~/Library/Caches folders already handled by a dedicated tool.
    private static let coveredCaches: Set<String> = [
        "Homebrew", "CocoaPods", "pip", "pypoetry", "go-build", "Yarn", "pnpm", "JetBrains",
        "com.apple.dt.Xcode", "org.swift.swiftpm", "org.carthage.CarthageKit", "claude-cli-nodejs",
        "Google", "com.microsoft.VSCode.ShipIt",
    ]

    static func appCaches() -> [CacheNode] {
        let t = ToolKind.apps
        var out: [CacheNode] = []

        // Electron / Chromium apps keep their caches in Application Support.
        let electron: [(String, String, String, [String])] = [
            ("Slack", "Slack", "com.tinyspeck.slackmacgap", ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage"]),
            ("Discord", "discord", "com.hnc.Discord", ["Cache", "Code Cache", "GPUCache"]),
            ("Microsoft Teams", "Microsoft/Teams", "com.microsoft.teams", ["Cache", "Code Cache", "GPUCache"]),
            ("Figma", "Figma", "com.figma.Desktop", ["Cache", "Code Cache", "GPUCache"]),
            ("Notion", "Notion", "notion.id", ["Cache", "Code Cache", "GPUCache"]),
        ]
        for (name, folder, bundle, subs) in electron {
            let base = Paths.url("Library/Application Support/\(folder)")
            guard exists(base) else { continue }
            let rows = subs.compactMap { sub -> CacheNode? in
                let u = base.appendingPathComponent(sub, isDirectory: true)
                return optionalLeaf("apps.\(folder).\(sub)", sub, u, t, risk: .safe,
                                    note: L("\(name) cache, recreated when the app opens. Messages and sign-in are not affected. Quit \(name) before deleting.",
                                          "Cache của \(name), tự tạo lại khi mở app. Tin nhắn và đăng nhập không bị ảnh hưởng. Thoát \(name) trước khi xoá."),
                                    action: quit(rm(u), bundle))
            }
            if !rows.isEmpty { out.append(group("apps.\(folder)", name, base, t, children: rows)) }
        }

        // Chrome's disk cache
        let chrome = Paths.url("Library/Caches/Google/Chrome")
        if let n = optionalLeaf("apps.chrome", "Google Chrome", chrome, t, risk: .safe,
                                note: L("Chrome's web page cache. History, passwords and tabs are not affected. Quit Chrome before deleting.",
                                      "Cache trang web của Chrome. Lịch sử, mật khẩu và tab không bị ảnh hưởng. Thoát Chrome trước khi xoá."),
                                action: quit(rmContents(chrome), "com.google.Chrome"), minSize: 1_000_000) {
            out.append(n)
        }

        // Everything else in ~/Library/Caches (third-party apps only, ≥ 10 MB).
        let caches = Paths.url("Library/Caches")
        let others = subdirs(caches)
            .filter { u in
                // Only reverse-DNS folders (com.vendor.App) from third parties. Apple also keeps
                // un-prefixed system caches here (CloudKit, GeoServices, Metadata…), which are skipped.
                let name = u.lastPathComponent
                return !coveredCaches.contains(name) && !name.hasPrefix("com.apple.")
                    && name.split(separator: ".").count >= 3
            }
            .compactMap { u -> CacheNode? in
                let name = u.lastPathComponent
                var action = rm(u)
                action.requiresQuitBundleID = name
                return optionalLeaf("apps.caches.\(name)", name, u, t, risk: .safe,
                                    note: L("Cache of the app \(name). The app recreates it when needed; quit the app before deleting.",
                                          "Cache của ứng dụng \(name). Ứng dụng tự tạo lại khi cần; nên thoát ứng dụng trước khi xoá."),
                                    action: action, minSize: 10_000_000)
            }
            .sorted { $0.leafSize > $1.leafSize }
        if !others.isEmpty {
            out.append(group("apps.caches", L("Other apps (~/Library/Caches)", "Ứng dụng khác (~/Library/Caches)"), caches, t, children: others))
        }
        return out
    }

    // MARK: - macOS

    static func macOS() -> [CacheNode] {
        let t = ToolKind.system
        var out: [CacheNode] = []
        let fm = FileManager.default

        // Logs
        let logs = Paths.url("Library/Logs")
        let crash = logs.appendingPathComponent("DiagnosticReports", isDirectory: true)
        var logRows: [CacheNode] = []
        if let n = optionalLeaf("sys.crash", L("Crash reports", "Báo cáo crash"), crash, t, risk: .safe,
                                note: L("Old app crash and hang reports. Only needed if you're filing a bug report.",
                                      "Báo cáo crash và hang cũ của ứng dụng. Chỉ cần khi đang gửi báo lỗi."),
                                action: rmContents(crash)) {
            logRows.append(n)
        }
        let coveredLogs: Set<String> = ["DiagnosticReports", "JetBrains", "Homebrew"]
        for u in subdirs(logs) where !coveredLogs.contains(u.lastPathComponent) {
            if let n = optionalLeaf("sys.logs.\(u.lastPathComponent)", u.lastPathComponent, u, t, risk: .safe,
                                    note: L("\(u.lastPathComponent) logs. The app writes new logs on its own.",
                                          "Log của \(u.lastPathComponent). Ứng dụng tự ghi log mới."),
                                    action: rm(u), minSize: 1_000_000) {
                logRows.append(n)
            }
        }
        if !logRows.isEmpty {
            out.append(group("sys.logs", L("User logs", "Log người dùng"), logs, t, children: logRows.sorted { $0.leafSize > $1.leafSize }))
        }

        // Trash
        let trash = Paths.url(".Trash")
        if let n = optionalLeaf("sys.trash", L("Trash", "Thùng rác"), trash, t, risk: .safe,
                                note: L("Items you've moved to the Trash. Same as Finder's “Empty Trash”.",
                                      "Những thứ bạn đã chuyển vào Thùng rác. Dọn tương đương “Dọn sạch Thùng rác” của Finder."),
                                action: rmContents(trash)) {
            out.append(n)
        }

        // Installers in Downloads (only once reading Downloads can't pop a surprise prompt)
        let downloads = Paths.url("Downloads")
        let exts: Set<String> = ["dmg", "pkg", "mpkg", "xip", "ipsw"]
        let files = (ProtectedFolders.mayAccess("Downloads")
                     ? ((try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                     : [])
            .filter { exts.contains($0.pathExtension.lowercased()) }
        let installerRows = files.compactMap { f -> CacheNode? in
            optionalLeaf("sys.dl.\(f.lastPathComponent)", f.lastPathComponent, f, t, risk: .rebuild,
                         note: L("Downloaded installer. Re-download it from the developer's site if you need to reinstall.",
                         "File cài đặt đã tải về. Tải lại từ trang của nhà phát hành nếu cần cài lại."),
                         action: CleanAction(removeURL: f, display: "rm -f " + Paths.shellDisplay(f)), minSize: 1_000_000)
        }
        .sorted { $0.leafSize > $1.leafSize }
        if !installerRows.isEmpty {
            out.append(group("sys.downloads", L("Installers in Downloads", "Bộ cài trong Downloads"), downloads, t, children: installerRows))
        }

        #if !APPSTORE
        // Leftover macOS installers in /Applications
        let apps = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let macInstallers = ((try? fm.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Install macOS") && $0.pathExtension == "app" }
            .compactMap { u -> CacheNode? in
                optionalLeaf("sys.macinstaller.\(u.lastPathComponent)", u.deletingPathExtension().lastPathComponent, u, t,
                             risk: .rebuild, note: L("Leftover macOS installer. Re-download it from the App Store if needed.",
                                     "Bộ cài macOS còn sót lại. Tải lại từ App Store nếu cần."),
                             action: CleanAction(removeURL: u, display: "rm -rf " + Paths.shellDisplay(u)))
            }
        out += macInstallers
        #endif

        // iPhone / iPad software updates
        for (id, name) in [("iPhone", L("iPhone updates (.ipsw)", "Cập nhật iPhone (.ipsw)")),
                         ("iPad", L("iPad updates (.ipsw)", "Cập nhật iPad (.ipsw)"))] {
            let u = Paths.url("Library/iTunes/\(id) Software Updates")
            if let n = optionalLeaf("sys.ipsw.\(id)", name, u, t, risk: .rebuild,
                                    note: L("iOS software files Finder downloaded to update/restore a device. Re-downloaded when needed.",
                                          "File phần mềm iOS do Finder tải khi cập nhật/khôi phục thiết bị. Tải lại khi cần."),
                                    action: rmContents(u), minSize: 1_000_000) {
                out.append(n)
            }
        }

        // Mail attachments that were opened (copies – originals stay in the mailbox)
        // Inside another app's container: only when that can't pop the "data from other apps" prompt.
        let mail = Paths.url("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        if ProtectedFolders.mayMeasureContainers, let n = optionalLeaf("sys.maildl", L("Opened Mail attachments", "Tệp Mail đã mở"), mail, t, risk: .safe,
                                note: L("Copies Mail makes of attachments when you open them. The originals stay in your email.",
                                      "Bản sao file đính kèm Mail tạo ra khi bạn mở chúng. Bản gốc vẫn nằm trong email."),
                                action: rmContents(mail), minSize: 1_000_000) {
            out.append(n)
        }
        return out
    }
}
