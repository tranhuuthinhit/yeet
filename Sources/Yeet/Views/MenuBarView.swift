import AppKit
import SwiftUI

/// Settings key: show the menu bar item and keep running in the background after the
/// window is closed (default on).
enum BackgroundMode {
    static let key = "menuBarEnabled"
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// Small panel shown from the menu bar icon.
struct MenuBarView: View {
    @Environment(GrowthStore.self) private var growth
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppLanguage.key) private var language = AppLanguage.en.rawValue

    private var disk: DiskInfo {
        var info = DiskInfo()
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                                          .volumeAvailableCapacityForImportantUsageKey]) {
            info.total = Int64(v.volumeTotalCapacity ?? 0)
            info.free = v.volumeAvailableCapacityForImportantUsage ?? 0
        }
        return info
    }

    var body: some View {
        let delta: Int64? = growth.current.flatMap { c in growth.baseline.map { c.diskUsed - $0.diskUsed } }
        let cause = GrowthScanner.topCause(growth.tree)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Yeet").font(.system(size: 14, weight: .semibold))
                    Text(L("\(Fmt.size(disk.free)) free of \(Fmt.capacity(disk.total))", "\(Fmt.size(disk.free)) trống / \(Fmt.capacity(disk.total))"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(growth.baseline.map { L("Compared with \(Fmt.modified($0.date))", "So với \(Fmt.modified($0.date))") }
                     ?? L("No data to compare yet", "Chưa có số liệu để so sánh"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let delta {
                    Text(Fmt.delta(delta))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(delta > 0 ? DS.danger : DS.success)
                }
                if let cause, cause.delta > 0 {
                    Text(L("Biggest growth: \(cause.displayPath) (\(Fmt.delta(cause.delta)))", "Tăng nhiều nhất: \(cause.displayPath) (\(Fmt.delta(cause.delta)))"))
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 6) {
                if growth.isCapturing {
                    ProgressView().controlSize(.mini)
                    Text(L("Analyzing… \(Fmt.count(growth.progressFiles)) \(growth.progressFiles == 1 ? "file" : "files")",
                           "Đang phân tích… \(Fmt.count(growth.progressFiles)) tệp"))
                } else {
                    Text(growth.lastCaptureDate.map { L("Last snapshot: \(Fmt.modified($0))", "Lần chụp gần nhất: \(Fmt.modified($0))") }
                         ?? L("No snapshots yet", "Chưa chụp lần nào"))
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Divider()

            VStack(spacing: 6) {
                if growth.isCapturing {
                    Button {
                        growth.cancelCapture()
                    } label: {
                        Label(growth.isCancelling ? L("Stopping…", "Đang dừng…") : L("Stop Analysis", "Dừng phân tích"), systemImage: "stop.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(growth.isCancelling)
                } else {
                    Button {
                        growth.capture()
                    } label: {
                        Label(L("Analyze Now", "Phân tích ngay"), systemImage: "camera.metering.center.weighted")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button {
                    AppActivation.showMainWindow(openWindow)
                } label: {
                    Label(L("Open Yeet", "Mở Yeet"), systemImage: "macwindow")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(L("Quit Yeet", "Thoát Yeet"), systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13))
        }
        .padding(14)
        .frame(width: 300)
        .id(language)
    }
}

/// Dock icon / window handling for background mode.
enum AppActivation {
    /// Brings the main window back (and the Dock icon).
    @MainActor
    static func showMainWindow(_ openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// After the last regular window closes in background mode, drop the Dock icon.
    @MainActor
    static func windowWillClose(_ closing: NSWindow) {
        guard BackgroundMode.isOn else { return }
        // Minimized windows count too: in .accessory mode their Dock tile would vanish.
        let others = NSApp.windows.filter {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.canBecomeMain && !($0 is NSPanel)
        }
        if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    /// A regular window became key while the Dock icon was hidden: show the Dock icon again.
    @MainActor
    static func windowDidBecomeKey(_ window: NSWindow) {
        guard NSApp.activationPolicy() == .accessory, window.canBecomeMain, !(window is NSPanel) else { return }
        NSApp.setActivationPolicy(.regular)
    }
}
