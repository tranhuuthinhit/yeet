import AppKit
import SwiftUI

/// Grouped module list on translucent dark glass; each row has a gradient tile in its module's hue
/// and a live figure on the right (size, count or status).
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrowthStore.self) private var growth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                Text("Yeet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS.text)
                Spacer()
                Text("v2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.text2)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }
            .padding(.horizontal, 18)
            .padding(.top, 38)      // clear of the traffic lights (hidden title bar)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ModuleSection.allCases, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            OverlineText(section.title)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 4)
                            ForEach(Module.modules(in: section)) { m in
                                SidebarRow(module: m, figure: figure(for: m), selected: model.module == m) {
                                    model.select(m)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            Rectangle().fill(DS.divider).frame(height: 1)
            DiskFooter()
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .background(DS.sidebar)
    }

    /// Right-hand figure of a row ("…" until the module has scanned).
    private func figure(for m: Module) -> String {
        switch m {
        case .overview:
            return model.scanned.isEmpty ? "…" : Fmt.size(model.grandTotal + LargeFilesStore.shared.total
                                                           + DuplicatesStore.shared.total + BrowsersStore.shared.total)
        case .devCaches, .systemJunk:
            return model.scanned.isEmpty ? "…" : Fmt.size(model.moduleNode(m).size)
        case .largeFiles:
            let s = LargeFilesStore.shared
            return s.scanned ? Fmt.size(s.total) : ""
        case .duplicates:
            let s = DuplicatesStore.shared
            return s.scanned ? Fmt.size(s.total) : ""
        case .browsers:
            let s = BrowsersStore.shared
            return s.scanned ? Fmt.size(s.total) : ""
        case .apps:
            let s = UninstallerStore.shared
            return s.scanned ? "\(s.apps.count)" : ""
        case .startup:
            let s = StartupStore.shared
            return s.scanned ? "\(s.items.count)" : ""
        case .growth:
            guard let c = growth.current, let b = growth.baseline else { return "" }
            return Fmt.delta(c.diskUsed - b.diskUsed)
        case .health:
            let h = HealthStore.shared
            return h.loaded ? (h.overallOK ? L("Good", "Tốt") : L("Check", "Kiểm tra")) : ""
        }
    }
}

private struct SidebarRow: View {
    let module: Module
    let figure: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(module.hue.tile)
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: module.symbol)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white))
                Text(module.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(figure)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(DS.text2)
            }
            .foregroundStyle(DS.text)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.14) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.2), value: selected)
    }
}

/// Disk name, used/free bar and the running "freed" total.
private struct DiskFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let disk = model.disk
        let total = max(Double(disk.total), 1)
        let usedFrac = min(1, Double(disk.total - disk.free) / total)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").font(.system(size: 13))
                Text(disk.name).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(DS.text)

            GeometryReader { g in
                Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF8A3D), Color(hex: 0xE0336B)],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * usedFrac)
            }
            .frame(height: 5)
            .background(Capsule().fill(DS.diskTrack))

            HStack {
                Text(L("\(Fmt.size(disk.free)) free of \(Fmt.capacity(disk.total))",
                       "\(Fmt.size(disk.free)) trống / \(Fmt.capacity(disk.total))"))
                Spacer()
            }
            .font(.system(size: 11.5))
            .monospacedDigit()
            .foregroundStyle(DS.text2)

            if model.freedTotal > 0 {
                Text(L("Freed so far: \(Fmt.size(model.freedTotal))", "Đã giải phóng: \(Fmt.size(model.freedTotal))"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(DS.success)
            }
        }
    }
}
