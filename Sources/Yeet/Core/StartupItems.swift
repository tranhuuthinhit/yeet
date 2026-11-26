// Logic ported from MacSweep (https://github.com/nihal4/macsweep), MIT License, Copyright (c) 2026 S. M. Nihal Ahmed.
//
// Launch agents & daemons, with orphan detection. Read-only in the App Sandbox: Yeet can't
// unload agents and never writes to ~/Library/LaunchAgents, so the screen only lists them,
// reveals their plist in Finder and points to System Settings › General › Login Items.

import AppKit
import Foundation
import Observation
import Security

enum StartupScope: Sendable {
    /// ~/Library/LaunchAgents
    case user
    /// /Library/LaunchAgents or /Library/LaunchDaemons (all users)
    case system
}

enum StartupKind: Sendable {
    case agent, daemon
}

struct StartupItem: Identifiable, Sendable {
    /// The plist path.
    var id: String { plistURL.path }
    let label: String
    let plistURL: URL
    /// Program (or first program argument); may be empty or relative for `BundleProgram` items.
    let programPath: String
    let scope: StartupScope
    let kind: StartupKind
    /// The program it starts no longer exists (its app is already gone).
    let isOrphan: Bool
    /// The program isn't signed by Apple or by an identified developer.
    let isUnknownSigner: Bool

    /// "User agent", "System agent", "System daemon".
    var kindTitle: String {
        switch (scope, kind) {
        case (.user, .agent): return L("User agent", "Agent người dùng")
        case (.user, .daemon): return L("User daemon", "Daemon người dùng")
        case (.system, .agent): return L("System agent", "Agent hệ thống")
        case (.system, .daemon): return L("System daemon", "Daemon hệ thống")
        }
    }
}

@Observable
final class StartupStore {
    static let shared = StartupStore()

    var items: [StartupItem] = []
    var scanning = false
    var scanned = false

    var orphanCount: Int { items.filter(\.isOrphan).count }
    var unknownSignerCount: Int { items.filter(\.isUnknownSigner).count }
    var userCount: Int { items.filter { $0.scope == .user }.count }

    @MainActor
    func scan() {
        guard !scanning else { return }
        scanning = true
        Task { @MainActor in
            let found: [StartupItem] = await Task.detached(priority: .userInitiated) {
                StartupScanner.load()
            }.value
            self.items = found
            self.scanning = false
            self.scanned = true
        }
    }

    @MainActor
    func reveal(_ item: StartupItem) {
        FileOps.reveal(item.plistURL)
    }

    /// System Settings › General › Login Items (the only place macOS lets you turn these off).
    @MainActor
    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum StartupScanner {
    static func load() -> [StartupItem] {
        let sources: [(URL, StartupScope, StartupKind)] = [
            (Paths.home.appendingPathComponent("Library/LaunchAgents", isDirectory: true), .user, .agent),
            (URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true), .system, .agent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true), .system, .daemon),
        ]
        var items: [StartupItem] = []
        let fm = FileManager.default
        for (dir, scope, kind) in sources {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
            for f in files where f.pathExtension == "plist" {
                items.append(parse(f, scope: scope, kind: kind))
            }
        }
        // Orphans first, then by label.
        return items.sorted { a, b in
            if a.isOrphan != b.isOrphan { return a.isOrphan }
            return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
        }
    }

    static func parse(_ url: URL, scope: StartupScope, kind: StartupKind) -> StartupItem {
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let d = obj as? [String: Any] {
            dict = d
        }
        let label = (dict["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        var program = ""
        if let p = dict["Program"] as? String {
            program = p
        } else if let args = dict["ProgramArguments"] as? [Any], let first = args.first as? String {
            program = first
        } else if let p = dict["BundleProgram"] as? String {
            program = p   // relative to its app (SMAppService); not checked
        }
        let absolute = program.hasPrefix("/")
        let orphan = absolute && isMissing(program)
        let unknown = absolute && !orphan && isUnknownSigner(program)
        return StartupItem(label: label, plistURL: url, programPath: program, scope: scope, kind: kind,
                           isOrphan: orphan, isUnknownSigner: unknown)
    }

    /// True only when the program is really gone: its nearest existing parent folder can be
    /// listed (so a sandbox denial is never mistaken for a missing file).
    static func isMissing(_ path: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) { return false }
        var parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        while parent.path != "/" && !fm.fileExists(atPath: parent.path) {
            parent = parent.deletingLastPathComponent()
        }
        return (try? fm.contentsOfDirectory(atPath: parent.path)) != nil
    }

    /// Unsigned, ad-hoc signed or unreadable signature, for programs outside Apple's own folders.
    static func isUnknownSigner(_ path: String) -> Bool {
        let applePrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"]
        if applePrefixes.contains(where: { path.hasPrefix($0) }) { return false }
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        guard created == errSecSuccess, let code = staticCode else { return false }
        var info: CFDictionary?
        // 1 << 1 = kSecCSSigningInformation
        let copied = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: 1 << 1), &info)
        guard copied == errSecSuccess, let dict = info as? [String: Any] else { return true }
        let identifier = dict[kSecCodeInfoIdentifier as String] as? String
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        if identifier == nil { return true }                       // not signed
        if let identifier, identifier.hasPrefix("com.apple.") { return false }
        return team == nil || team?.isEmpty == true                // ad-hoc / no developer
    }
}
