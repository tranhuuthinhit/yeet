import SwiftUI

/// Sidebar groups.
enum ModuleSection: String, CaseIterable {
    case overview, clean, apps, monitor

    var title: String {
        switch self {
        case .overview: return L("OVERVIEW", "TỔNG QUAN")
        case .clean: return L("CLEAN UP", "DỌN DẸP")
        case .apps: return L("APPS", "ỨNG DỤNG")
        case .monitor: return L("MONITOR", "THEO DÕI")
        }
    }
}

/// Top-level screens of Yeet v2 (one per sidebar row).
enum Module: String, CaseIterable, Identifiable, Hashable {
    case overview
    case devCaches, systemJunk, largeFiles, duplicates, browsers
    case apps, startup
    case growth, health

    var id: String { rawValue }

    var section: ModuleSection {
        switch self {
        case .overview: return .overview
        case .devCaches, .systemJunk, .largeFiles, .duplicates, .browsers: return .clean
        case .apps, .startup: return .apps
        case .growth, .health: return .monitor
        }
    }

    var title: String {
        switch self {
        case .overview: return L("Overview", "Tổng quan")
        case .devCaches: return L("Developer Caches", "Cache lập trình")
        case .systemJunk: return L("System Junk", "Rác hệ thống")
        case .largeFiles: return L("Large & Old Files", "File lớn & cũ")
        case .duplicates: return L("Duplicates", "File trùng")
        case .browsers: return L("Browsers", "Trình duyệt")
        case .apps: return L("Uninstaller", "Gỡ ứng dụng")
        case .startup: return L("Startup Items", "Mục khởi động")
        case .growth: return L("Disk Growth", "Tăng trưởng ổ đĩa")
        case .health: return L("Mac Health", "Sức khoẻ máy")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .devCaches: return "chevron.left.forwardslash.chevron.right"
        case .systemJunk: return "trash.fill"
        case .largeFiles: return "doc.fill"
        case .duplicates: return "square.on.square.fill"
        case .browsers: return "globe"
        case .apps: return "app.badge.fill"
        case .startup: return "power"
        case .growth: return "chart.line.uptrend.xyaxis"
        case .health: return "waveform.path.ecg"
        }
    }

    var hue: Hue {
        switch self {
        case .overview: return .violet
        case .devCaches: return .green
        case .systemJunk: return .amber
        case .largeFiles: return .orange
        case .duplicates: return .indigo
        case .browsers: return .cyan
        case .apps: return .blue
        case .startup: return .teal
        case .growth: return .rose
        case .health: return .crimson
        }
    }

    /// Cache tools listed by the two cache modules.
    var cacheSection: ToolSection? {
        switch self {
        case .devCaches: return .dev
        case .systemJunk: return .apps
        default: return nil
        }
    }

    static func modules(in section: ModuleSection) -> [Module] {
        allCases.filter { $0.section == section }
    }
}

// MARK: - Review before cleaning

/// What happens to an item when the user confirms.
enum CleanMethod: Int, CaseIterable, Comparable {
    case delete    // permanently removed (caches that are recreated)
    case trash     // moved to the Trash (can be put back)

    static func < (a: CleanMethod, b: CleanMethod) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .delete: return L("Delete permanently", "Xoá vĩnh viễn")
        case .trash: return L("Move to Trash", "Chuyển vào Thùng rác")
        }
    }

    var hint: String {
        switch self {
        case .delete: return L("Caches that are recreated automatically", "Cache tự tạo lại được")
        case .trash: return L("You can put these back from the Trash", "Khôi phục được từ Thùng rác")
        }
    }

    var color: Color {
        switch self {
        case .delete: return Color(hex: 0xFFA552)
        case .trash: return Color(hex: 0x45D6A0)
        }
    }
}

struct ReviewItem: Identifiable {
    let id: String
    let title: String
    /// Path shown under the title (tilde form).
    let detail: String
    let size: Int64
    let method: CleanMethod
}

/// A confirmation request shown as the "Review before cleaning" sheet. Any module can post one.
struct ReviewRequest: Identifiable {
    let id = UUID()
    var title: String = L("Review Before Cleaning", "Xem lại trước khi dọn")
    let items: [ReviewItem]
    /// Blocking problems shown above the list (e.g. "Quit Chrome first").
    var warnings: [String] = []
    /// Label of the confirm button; defaults to "Clean <size>".
    var confirmLabel: String? = nil
    let perform: @MainActor () -> Void

    var total: Int64 { items.reduce(0) { $0 + $1.size } }
}
