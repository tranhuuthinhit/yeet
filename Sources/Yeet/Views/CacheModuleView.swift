import SwiftUI

/// "Developer Caches" and "System Junk": tool chips, risk filter, cache tree + inspector,
/// and the bottom action bar that opens the review sheet.
struct CacheModuleView: View {
    let module: Module
    @Environment(AppModel.self) private var model
    @Environment(\.hue) private var hue
    @AppStorage(GitRoots.key) private var gitRootsRaw = GitRoots.defaultValue

    var body: some View {
        @Bindable var model = model
        let riskOptions: [(value: Risk?, label: String)] = [
            (nil, L("All", "Tất cả")), (.safe, Risk.safe.label), (.rebuild, Risk.rebuild.label), (.caution, Risk.caution.label),
        ]

        VStack(spacing: 0) {
            ModuleHeader(module.title, subtitle: subtitle) {
                SegmentedPill(selection: $model.riskFilter, options: riskOptions)
                Button {
                    model.rescan()
                } label: {
                    HStack(spacing: 6) {
                        SpinningIcon(systemName: "arrow.clockwise", active: model.phase == .scanning)
                        Text(model.phase == .scanning ? L("Scanning…", "Đang quét…") : L("Rescan", "Quét lại"))
                    }
                }
                .buttonStyle(OutlineButtonStyle(height: 32, fontSize: 13, horizontalPadding: 12))
                .disabled(model.phase != .idle)
                .help(L("Rescan all caches (⌘R)", "Quét lại toàn bộ cache (⌘R)"))
            }

            toolChips
                .padding(.top, 14)

            if let k = model.toolFilter {
                Text(k.description(gitRoots: GitRoots.list(gitRootsRaw)))
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            HStack(alignment: .top, spacing: 16) {
                CacheTreeView()
                InspectorView().frame(width: 320)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxHeight: .infinity)

            CacheActionBar(module: module)
        }
    }

    private var subtitle: String {
        let node = model.moduleNode(module)
        let safe = node.leaves.filter { $0.risk == .safe }.reduce(Int64(0)) { $0 + $1.leafSize }
        let n = model.tools(in: module).count
        return L("\(n) tools · \(Fmt.size(node.size)) · \(Fmt.size(safe)) safe to delete",
                 "\(n) công cụ · \(Fmt.size(node.size)) · \(Fmt.size(safe)) an toàn để xoá")
    }

    private var toolChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(name: L("All", "Tất cả"), size: Fmt.size(model.moduleNode(module).size),
                     color: .white, selected: model.toolFilter == nil) { model.toolFilter = nil }
                ForEach(model.tools(in: module)) { k in
                    chip(name: k.name, size: model.scanned.contains(k) ? Fmt.size(model.toolNode(k).size) : "…",
                         color: k.color, selected: model.toolFilter == k) {
                        model.toolFilter = k
                        model.focus(model.items[k]?.first?.id ?? k.rawValue)
                    }
                    .contextMenu {
                        Button(L("Hide \(k.name)", "Ẩn \(k.name)")) { model.setHidden(k, true) }
                        SettingsLink { Text(L("Manage Tools…", "Quản lý công cụ…")) }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func chip(name: String, size: String, color: Color, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(selected ? hue.tileDark : color).frame(width: 8, height: 8)
                Text(name).font(.system(size: 12.5, weight: selected ? .bold : .medium))
                Text(size).font(.system(size: 12.5)).monospacedDigit().opacity(0.85)
            }
            .foregroundStyle(selected ? hue.ink : DS.text)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(selected ? Color.white : Color.white.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Selection summary, cleaning progress, "Select Safe Items" and "Review & Clean…".
struct CacheActionBar: View {
    let module: Module
    @Environment(AppModel.self) private var model
    @AppStorage("confirmBeforeClean") private var confirmBeforeClean = true

    var body: some View {
        let sel = model.selectedLeaves(in: module)
        let size = sel.reduce(Int64(0)) { $0 + $1.leafSize }
        let node = model.moduleNode(module)

        ActionBar {
            SelectionSummary(
                title: L("Selected \(sel.count == 1 ? "1 item" : "\(sel.count) items") · \(Fmt.size(size))",
                         "Đã chọn \(sel.count) mục · \(Fmt.size(size))"),
                detail: L("Total: \(Fmt.size(node.size)) · “Caution” items are never pre-selected",
                          "Tổng: \(Fmt.size(node.size)) · Mục “Thận trọng” không bao giờ được chọn sẵn"))
        } actions: {
            if case .cleaning(let p) = model.phase {
                HStack(spacing: 10) {
                    ProgressView(value: p).progressViewStyle(.linear).tint(.white).frame(width: 160)
                    Text(L("Cleaning… \(Int((p * 100).rounded()))%", "Đang dọn… \(Int((p * 100).rounded()))%"))
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(DS.text2)
                }
            }
            Button {
                model.selectSafe()
            } label: {
                Label(L("Select Safe Items", "Chọn mục an toàn"), systemImage: "checkmark.shield")
            }
            .buttonStyle(OutlineButtonStyle(height: 36))
            .disabled(model.phase != .idle)

            Button(L("Review & Clean…", "Xem lại & dọn…")) {
                model.requestClean(confirm: confirmBeforeClean)
            }
            .buttonStyle(FilledButtonStyle())
            .disabled(sel.isEmpty || model.phase != .idle)
        }
    }
}
