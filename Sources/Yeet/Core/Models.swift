import SwiftUI

// MARK: - Risk

enum Risk: String, Sendable, Hashable {
    case safe, rebuild, caution

    var label: String {
        switch self {
        case .safe: return L("Safe", "An toàn")
        case .rebuild: return L("Re-download", "Tải lại")
        case .caution: return L("Caution", "Thận trọng")
        }
    }

    var color: Color {
        switch self {
        case .safe: return Color(hex: 0x1E8A5E)
        case .rebuild: return Color(hex: 0x8A5A00)
        case .caution: return Color(hex: 0xE03131)
        }
    }

    var tint: Color {
        switch self {
        case .safe: return Color(hex: 0x2BA776, opacity: 0.15)
        case .rebuild: return Color(hex: 0xF2B441, opacity: 0.18)
        case .caution: return Color(hex: 0xE03131, opacity: 0.12)
        }
    }
}

// MARK: - Tools

enum ToolSection: String, CaseIterable {
    case dev, apps

    var title: String {
        switch self {
        case .dev: return L("DEVELOPER TOOLS", "CÔNG CỤ LẬP TRÌNH")
        case .apps: return L("APPS & SYSTEM", "ỨNG DỤNG & HỆ THỐNG")
        }
    }
}

enum ToolKind: String, CaseIterable, Identifiable, Sendable, Hashable {
    // Sidebar order
    case xcode, swiftDeps, npm, yarn, pnpm, nodeModules, python, go, rust, gradle, maven, flutter, homebrew, git, claude
    case ide, apps, system

    var id: String { rawValue }

    /// Tools offered in this build. The sandboxed App Store build can't run `git`
    /// (and must not delete Git data directly), so Git is left out there.
    static var available: [ToolKind] {
        #if APPSTORE
        return allCases.filter { $0 != .git }
        #else
        return allCases
        #endif
    }

    var section: ToolSection {
        switch self {
        case .ide, .apps, .system: return .apps
        default: return .dev
        }
    }

    var name: String {
        switch self {
        case .xcode: return "App Builds"
        case .swiftDeps: return "CocoaPods & SPM"
        case .npm: return "npm"
        case .yarn: return "Yarn"
        case .pnpm: return "pnpm & Bun"
        case .nodeModules: return "node_modules"
        case .python: return "Python"
        case .go: return "Go"
        case .rust: return "Rust"
        case .gradle: return "Gradle"
        case .maven: return "Maven"
        case .flutter: return "Flutter & Dart"
        case .homebrew: return "Homebrew"
        case .git: return "Git"
        case .claude: return "Claude Code"
        case .ide: return "IDE & Editor"
        case .apps: return L("App Caches", "Cache ứng dụng")
        case .system: return "macOS"
        }
    }

    var color: Color {
        switch self {
        case .xcode: return Color(hex: 0x2E5C8A)
        case .swiftDeps: return Color(hex: 0xF05138)
        case .npm: return Color(hex: 0xE03131)
        case .yarn: return Color(hex: 0x5B8DB8)
        case .pnpm: return Color(hex: 0xE8A317)
        case .nodeModules: return Color(hex: 0x5FA04E)
        case .python: return Color(hex: 0x3776AB)
        case .go: return Color(hex: 0x00ADD8)
        case .rust: return Color(hex: 0xB7410E)
        case .gradle: return Color(hex: 0x2BA776)
        case .maven: return Color(hex: 0xC71A36)
        case .flutter: return Color(hex: 0x02569B)
        case .homebrew: return Color(hex: 0xC98A2B)
        case .git: return Color(hex: 0xF07B3F)
        case .claude: return Color(hex: 0xF2B441)
        case .ide: return Color(hex: 0x007ACC)
        case .apps: return Color(hex: 0x7B61D9)
        case .system: return Color(hex: 0x5A6778)
        }
    }

    var symbol: String {
        switch self {
        case .xcode: return "hammer.fill"
        case .swiftDeps: return "swift"
        case .npm: return "shippingbox.fill"
        case .yarn: return "cube.fill"
        case .pnpm: return "archivebox.fill"
        case .nodeModules: return "folder.fill"
        case .python: return "curlybraces"
        case .go: return "hare.fill"
        case .rust: return "gearshape.2.fill"
        case .gradle: return "square.stack.3d.up.fill"
        case .maven: return "books.vertical.fill"
        case .flutter: return "bird.fill"
        case .homebrew: return "mug.fill"
        case .git: return "arrow.triangle.branch"
        case .claude: return "terminal.fill"
        case .ide: return "chevron.left.forwardslash.chevron.right"
        case .apps: return "square.stack.fill"
        case .system: return "internaldrive.fill"
        }
    }

    /// Root folder shown for the tool row.
    var rootPath: String {
        switch self {
        case .xcode: return "~/Library/Developer"
        case .swiftDeps: return "~/Library/Caches"
        case .npm: return "~/.npm"
        case .yarn: return "~/Library/Caches/Yarn"
        case .pnpm: return "~/Library/pnpm"
        case .nodeModules: return "~/Projects/**/node_modules"
        case .python: return "~/Library/Caches"
        case .go: return "~/go"
        case .rust: return "~/.cargo"
        case .gradle: return "~/.gradle"
        case .maven: return "~/.m2"
        case .flutter: return "~/.pub-cache"
        case .homebrew: return "~/Library/Caches/Homebrew"
        case .git: return "~/Projects/*/.git"
        case .claude: return "~/.claude"
        case .ide: return "~/Library/Application Support"
        case .apps: return "~/Library/Caches"
        case .system: return "~/Library"
        }
    }

    func description(gitRoots: [String]) -> String {
        let roots = gitRoots.isEmpty ? L("the project folders you chose in Settings", "thư mục dự án bạn chọn trong Cài đặt") : gitRoots.joined(separator: ", ")
        switch self {
        case .xcode:
            return L("DerivedData, Device Support, Simulator caches and old simulator runtimes — usually the biggest space hog on an iOS dev machine. Archives aren't listed because they can't be recreated.", "DerivedData, Device Support, cache Simulator và các simulator runtime cũ — thường là nguồn chiếm dung lượng lớn nhất trên máy dev iOS. Archives không được liệt kê vì không tạo lại được.")
        case .swiftDeps:
            return L("CocoaPods pod cache plus Swift Package Manager and Carthage package caches. They're re-downloaded on the next dependency install.", "Cache pod của CocoaPods, cache package của Swift Package Manager và Carthage. Lần cài dependency kế tiếp sẽ tải lại.")
        case .npm:
            return L("npm's package tarball cache and temporary packages downloaded by npx. Deleting them doesn't affect your projects' node_modules.", "Cache package tarball của npm và các gói tạm do npx tải về. Xoá không ảnh hưởng node_modules của dự án.")
        case .yarn:
            return L("Yarn Classic (v1) offline cache and Yarn Berry (v2+) global cache.", "Cache offline của Yarn Classic (v1) và global cache của Yarn Berry (v2+).")
        case .pnpm:
            return L("pnpm's content-addressable store and Bun's install cache. Existing node_modules keep working; the next install re-downloads packages.", "Content-addressable store của pnpm và cache cài đặt của Bun. node_modules hiện có vẫn chạy; lần cài kế tiếp sẽ tải lại.")
        case .nodeModules:
            return L("node_modules folders in projects under \(roots). Projects untouched for over 30 days are marked Safe; reinstall with npm/yarn/pnpm install.", "Thư mục node_modules trong các dự án ở \(roots). Dự án không đụng tới hơn 30 ngày được đánh dấu an toàn; cài lại bằng npm/yarn/pnpm install.")
        case .python:
            return L("pip, Poetry and uv caches plus Conda's pkgs folder. Virtualenvs and Conda environments are never touched.", "Cache của pip, Poetry, uv và thư mục pkgs của Conda. Không đụng tới virtualenv hay môi trường Conda.")
        case .go:
            return L("Go build cache and module cache. The next build recompiles and re-downloads modules.", "Build cache và module cache của Go. Lần build kế tiếp sẽ biên dịch và tải module lại.")
        case .rust:
            return L("Cargo's registry cache, extracted sources and git checkouts, plus the target/ folders of Rust projects under \(roots).", "Registry cache, source đã giải nén và git checkout của Cargo, cùng thư mục target/ của các dự án Rust ở \(roots).")
        case .gradle:
            return L("Dependencies, build cache, transforms and downloaded Gradle wrappers for Android/JVM projects.", "Dependency, build cache, transform và các bản Gradle wrapper đã tải cho dự án Android/JVM.")
        case .maven:
            return L("Maven's local repository (~/.m2). The next build re-downloads dependencies.", "Local repository của Maven (~/.m2). Lần build kế tiếp sẽ tải lại dependency.")
        case .flutter:
            return L("Flutter and Dart pub cache. Run flutter pub get to re-download.", "Pub cache của Flutter và Dart. Chạy flutter pub get để tải lại.")
        case .homebrew:
            return L("Homebrew downloads and logs. No installed packages are removed.", "Bản tải xuống và log của Homebrew. Không gỡ gói nào đang cài.")
        case .git:
            return L("Loose objects that git gc can pack, and Git LFS caches in repos found under \(roots).", "Object thừa có thể gom bằng git gc và cache Git LFS trong các repo tìm thấy ở \(roots).")
        case .claude:
            return L("Claude Code CLI shell snapshots, todos and logs, plus the Cowork VM (10–20 GB) and Claude desktop app caches. Session history isn't listed.", "Snapshot shell, todo và log của Claude Code CLI, cùng máy ảo Cowork (10–20 GB) và cache của app Claude desktop. Lịch sử phiên không được liệt kê.")
        case .ide:
            return L("VS Code, Cursor and JetBrains caches (old IDE versions only), plus logs. Quit your IDE before cleaning.", "Cache của VS Code, Cursor và JetBrains (chỉ các phiên bản IDE cũ), cùng log. Thoát IDE trước khi dọn.")
        case .apps:
            return L("Caches for Slack, Discord, Chrome and other apps in ~/Library/Caches. Apps recreate them when opened.", "Cache của Slack, Discord, Chrome và các ứng dụng khác trong ~/Library/Caches. Ứng dụng tự tạo lại khi mở.")
        case .system:
            return L("Logs and crash reports, the Trash, .dmg/.pkg installers in Downloads, macOS installers, iPhone update files (.ipsw) and downloaded Mail attachments.", "Log và báo cáo crash, Thùng rác, bộ cài .dmg/.pkg trong Downloads, bộ cài macOS, file cập nhật iPhone (.ipsw) và file đính kèm Mail đã tải.")
        }
    }
}

// MARK: - Clean action

struct CleanAction: Sendable, Hashable {
    /// Shell command (run through a login zsh) executed first, if any.
    var command: String? = nil
    /// Path removed afterwards (fallback / main action).
    var removeURL: URL? = nil
    /// Remove the folder's contents instead of the folder itself.
    var contentsOnly: Bool = false
    /// Extra paths removed together with `removeURL` (e.g. `.rootfs.img.origin` markers).
    var extraRemovals: [URL] = []
    /// Refuse to clean while the app with this bundle id is running (e.g. Claude desktop VM).
    var requiresQuitBundleID: String? = nil
    /// Human readable command shown in the inspector ("HOW TO CLEAN").
    var display: String
}

// MARK: - Tree node

struct CacheNode: Identifiable, Sendable, Hashable {
    let id: String
    var name: String
    var url: URL
    var tool: ToolKind
    var isTool: Bool = false
    var pathOverride: String? = nil
    var children: [CacheNode]? = nil
    var leafSize: Int64 = 0
    var fileCount: Int = 0
    var modified: Date? = nil
    var risk: Risk? = nil
    var note: String = ""
    var action: CleanAction? = nil

    var isGroup: Bool { children != nil }
    var path: String { pathOverride ?? Paths.tilde(url) }

    var size: Int64 {
        guard let children else { return leafSize }
        return children.reduce(Int64(0)) { $0 + $1.size }
    }

    var leaves: [CacheNode] {
        guard let children else { return [self] }
        return children.flatMap { $0.leaves }
    }

    /// Non-empty leaves – the only ones that can be checked.
    var liveLeaves: [CacheNode] { leaves.filter { $0.leafSize > 0 } }

    var latestModified: Date? {
        guard let children else { return modified }
        return children.compactMap { $0.latestModified }.max()
    }

    func find(_ id: String) -> CacheNode? {
        if self.id == id { return self }
        for c in children ?? [] {
            if let r = c.find(id) { return r }
        }
        return nil
    }
}

enum CheckState {
    case disabled, unchecked, partial, checked
}

enum Phase: Equatable {
    case idle
    case scanning
    case cleaning(Double)
}

enum ViewSelection: Hashable {
    case all
    case growth
    case tool(ToolKind)
}

struct DiskInfo: Equatable {
    var name: String = "Macintosh HD"
    var total: Int64 = 0
    var free: Int64 = 0
}
