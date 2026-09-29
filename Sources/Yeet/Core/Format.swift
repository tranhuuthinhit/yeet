import Foundation

enum Fmt {
    /// `0 KB`, `412 KB`, `640 MB`, `3.45 GB` (`3,45 GB` in Vietnamese; base-1000 like Finder).
    static func size(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        let kb = Double(bytes) / 1_000
        if kb < 1_000 { return "\(max(1, Int(kb.rounded()))) KB" }
        let mb = kb / 1_000
        if mb < 999.5 { return "\(Int(mb.rounded())) MB" }
        let gb = mb / 1_000
        let digits = mb >= 100_000 ? 1 : 2
        let text = String(format: "%.\(digits)f", gb)
        return (AppLanguage.current == .vi ? text.replacingOccurrences(of: ".", with: ",") : text) + " GB"
    }

    /// Whole-GB capacity, e.g. `494 GB`.
    static func capacity(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / 1_000_000_000).rounded())) GB"
    }

    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = AppLanguage.current.locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// `dd/MM/yyyy` in Vietnamese, `MMM d, yyyy` in English.
    static func date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.dateFormat = AppLanguage.current == .vi ? "dd/MM/yyyy" : "MMM d, yyyy"
        return f.string(from: date)
    }

    /// Relative time under 24h ("2 hours ago"), otherwise a short date.
    static func modified(_ date: Date?) -> String {
        guard let date else { return "—" }
        let s = Date().timeIntervalSince(date)
        if s < 60 { return L("Just now", "Vừa xong") }
        let m = Int(s / 60), h = Int(s / 3_600)
        if s < 3_600 { return L(m == 1 ? "1 minute ago" : "\(m) minutes ago", "\(m) phút trước") }
        if s < 86_400 { return L(h == 1 ? "1 hour ago" : "\(h) hours ago", "\(h) giờ trước") }
        return Self.date(date)
    }
}

enum Paths {
    /// The user's real home folder. Inside the App Sandbox `homeDirectoryForCurrentUser`
    /// points at the app container, so read it from the password database instead.
    static let home: URL = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    static func url(_ relative: String) -> URL {
        home.appendingPathComponent(relative, isDirectory: true)
    }

    /// `/Users/me/.npm` -> `~/.npm`
    static func tilde(_ url: URL) -> String {
        let p = url.path
        let h = home.path
        if p == h { return "~" }
        if p.hasPrefix(h + "/") { return "~" + String(p.dropFirst(h.count)) }
        return p
    }

    static func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true) }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Display form for shell commands: `~/"Library/Xcode/iOS DeviceSupport/17.5 (21F90)"`.
    static func shellDisplay(_ url: URL) -> String {
        let t = tilde(url)
        let needsQuote = t.contains { " ()'\"&;$`".contains($0) }
        guard needsQuote else { return t }
        if t.hasPrefix("~/") { return "~/\"" + String(t.dropFirst(2)) + "\"" }
        return "\"" + t + "\""
    }

    /// Safe single-quoted absolute path for the command that is actually executed.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum GitRoots {
    static let key = "gitRoots"
    static let defaultValue = "~/Projects\n~/Developer"

    static func list(_ raw: String) -> [String] {
        raw.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func currentList() -> [String] {
        list(UserDefaults.standard.string(forKey: key) ?? defaultValue)
    }

    static func load() -> [URL] { currentList().map(Paths.expand) }
}
