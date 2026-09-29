import AppKit
import SwiftUI

@main
struct YeetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var growth = GrowthStore.shared
    @AppStorage(BackgroundMode.key) private var menuBarEnabled = true

    init() {
        // Re-activate the sandboxed folder grant before any scan starts.
        FolderAccess.restore()
    }

    var body: some Scene {
        Window("Yeet", id: "main") {
            ContentView()
                .environment(model)
                .environment(growth)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CacheCommands(model: model, growth: growth)
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(growth)
                .preferredColorScheme(.light)
        }

        // Menu bar item: keeps Yeet (and the daily capture) running after the window is closed.
        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarView()
                .environment(growth)
        } label: {
            Image(systemName: "internaldrive")
        }
        .menuBarExtraStyle(.window)
    }
}

/// The "Cache" menu. Owns its own `@AppStorage` for the language so the menu items
/// re-render (and switch language) as soon as the user changes it in Settings.
struct CacheCommands: Commands {
    let model: AppModel
    let growth: GrowthStore
    @AppStorage("confirmBeforeClean") private var confirmBeforeClean = true
    @AppStorage(AppLanguage.key) private var language = AppLanguage.en.rawValue

    /// Like `L`, but reads the observed `language` so this body depends on it.
    private func t(_ en: String, _ vi: String) -> String {
        language == AppLanguage.vi.rawValue ? vi : en
    }

    var body: some Commands {
        CommandMenu("Cache") {
            Button(t("Rescan", "Quét lại")) { model.rescan() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.phase != .idle)
            Button(t("Analyze Disk Usage Now", "Phân tích dung lượng ngay")) {
                model.select(.growth)
                growth.capture()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(growth.isCapturing)
            Button(t("Stop Analysis", "Dừng phân tích")) { growth.cancelCapture() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!growth.isCapturing || growth.isCancelling)
            Divider()
            Button(t("Select Safe Items", "Chọn mục an toàn")) { model.selectSafe() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button(t("Deselect All", "Bỏ chọn tất cả")) { model.checked.removeAll() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button(t("Clean Up…", "Dọn dẹp…")) { model.requestClean(confirm: confirmBeforeClean) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedLeaves.isEmpty || model.phase != .idle)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when macOS started Yeet as a login item: start in the menu bar, without a window.
    static var launchedAtLogin = false
    private var closeObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 'oapp' event carrying keyAEPropData = keyAELaunchedAsLogInItem ('lgit').
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == 0x6F61_7070,                                    // kAEOpenApplication
           event.paramDescriptor(forKeyword: 0x7072_6474)?.enumCodeValue == 0x6C67_6974 {
            Self.launchedAtLogin = true
        } else if LoginItem.isEnabled && ProcessInfo.processInfo.systemUptime < 180 {
            Self.launchedAtLogin = true                                     // fresh boot fallback
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let onboarded = UserDefaults.standard.bool(forKey: "didOnboard")
        let ready = onboarded && (!BuildFlavor.isAppStore || FolderAccess.isGranted)
        // Same condition ContentView uses to dismiss the window; otherwise onboarding would
        // show up without a Dock icon / menu.
        let hidden = Self.launchedAtLogin && BackgroundMode.isOn && ready
        // .regular is also needed when launched as a bare SwiftPM executable (no .app bundle).
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        applyDockIcon()
        if !hidden { NSApp.activate(ignoringOtherApps: true) }

        // Background mode: drop the Dock icon once the last window closes.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in AppActivation.windowWillClose(window) }
        }
        // Any regular window shown while in accessory mode (reopen from Finder, SwiftUI
        // restoring the window) brings the Dock icon and menu back.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in AppActivation.windowDidBecomeKey(window) }
        }

        // Daily disk snapshots run even when no window is open.
        if ready {
            GrowthStore.shared.startSchedule()
        }
    }

    /// Makes sure the Dock shows Yeet's icon even when LaunchServices hasn't picked it up yet
    /// (fresh Debug builds in DerivedData) or when running from Package.swift / `swift run`,
    /// where there is no bundle and no asset catalog.
    private func applyDockIcon() {
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
            return
        }
        #if DEBUG
        // Source checkout: Sources/Yeet/YeetApp.swift → ../../Support/AppIcon.icns
        let icns = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Support/AppIcon.icns")
        if let icon = NSImage(contentsOf: icns) {
            NSApp.applicationIconImage = icon
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !BackgroundMode.isOn }
}
