import SwiftUI

/// "Startup Items": launch agents and daemons, read-only. In the App Sandbox Yeet can't turn
/// them off, so it flags orphans and unknown developers and points to System Settings.
@MainActor
struct StartupView: View {
    private var store: StartupStore { StartupStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(Module.startup.title, subtitle: subtitle) {
                Button {
                    store.scan()
                } label: {
                    Label(L("Rescan", "Quét lại"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(OutlineButtonStyle())
                .disabled(store.scanning)
            }

            VStack(spacing: 12) {
                infoBanner
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if !store.scanned && !store.scanning { store.scan() }
        }
    }

    private var subtitle: String {
        guard store.scanned else {
            return L("Apps and helpers that start with your Mac", "Ứng dụng và tiến trình chạy cùng máy Mac")
        }
        let n = store.items.count
        let o = store.orphanCount
        let items = L(n == 1 ? "1 background item" : "\(n) background items", "\(n) mục chạy nền")
        if o == 0 { return items + L(" · none orphaned", " · không có mục mồ côi") }
        return items + L(" · \(o) orphaned: their app is already gone", " · \(o) mục mồ côi: ứng dụng đã bị gỡ")
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(DS.text2)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("macOS only lets you turn these off in System Settings",
                       "macOS chỉ cho phép tắt các mục này trong Cài đặt hệ thống"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(L("Yeet lists what starts with your Mac and flags items whose app is gone or whose developer is unknown. Turn items off under General › Login Items & Extensions › Allow in the Background, or reveal an orphaned item in Finder and move it to the Trash yourself.",
                       "Yeet liệt kê những gì khởi động cùng máy và đánh dấu mục có ứng dụng đã bị gỡ hoặc nhà phát triển không rõ. Tắt chúng trong Cài đặt chung › Mục đăng nhập & Tiện ích mở rộng › Cho phép chạy nền, hoặc hiện mục mồ côi trong Finder rồi tự chuyển vào Thùng rác."))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(L("Open Login Items Settings", "Mở cài đặt Mục đăng nhập")) {
                StartupStore.openLoginItemsSettings()
            }
            .buttonStyle(FilledButtonStyle())
        }
        .padding(14)
        .card()
    }

    @ViewBuilder
    private var content: some View {
        if store.scanning && store.items.isEmpty {
            ModuleEmptyState(symbol: "power", title: L("Reading startup items…", "Đang đọc mục khởi động…"), busy: true)
                .card()
        } else if store.scanned && store.items.isEmpty {
            ModuleEmptyState(symbol: "checkmark.circle",
                             title: L("No launch agents or daemons found", "Không tìm thấy launch agent hay daemon nào"))
                .card()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { item in
                        StartupRow(item: item)
                        Rectangle().fill(DS.rowDivider).frame(height: 1)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
        }
    }
}

@MainActor
private struct StartupRow: View {
    let item: StartupItem

    var body: some View {
        HStack(spacing: 12) {
            if item.isOrphan {
                HueTile(symbol: "exclamationmark.triangle.fill", color: DS.warning, size: 32, glyph: 14)
            } else {
                HueTile(symbol: item.kind == .daemon ? "gearshape.2.fill" : "gearshape.fill", size: 32, glyph: 14)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.programPath.isEmpty ? Paths.tilde(item.plistURL) : item.programPath)
                    .font(DS.mono(11.5))
                    .foregroundStyle(DS.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.programPath)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Chip(text: item.kindTitle)
                if item.isOrphan {
                    Chip(text: L("Orphaned", "Mồ côi"), tint: DS.warning)
                }
                if item.isUnknownSigner {
                    Chip(text: L("Unknown developer", "Nhà phát triển không rõ"), tint: DS.warning)
                }
            }
            Button(L("Reveal", "Hiện")) { FileOps.reveal(item.plistURL) }
                .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 12))
                .help(L("Reveal the plist in Finder", "Hiện file plist trong Finder"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contextMenu {
            Button(L("Reveal in Finder", "Hiện trong Finder")) { FileOps.reveal(item.plistURL) }
        }
    }
}
