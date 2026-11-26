import SwiftUI

/// Uninstaller › Extensions: editor extensions and JetBrains plugins with the architecture of the
/// native code they ship, so Intel-only ones (that need Rosetta) stand out.
@MainActor
struct ExtensionsPanel: View {
    let search: String
    @Environment(AppModel.self) private var model
    private var store: ExtensionsStore { .shared }

    var body: some View {
        VStack(spacing: 12) {
            if store.scanned && store.rosettaCount > 0 {
                RosettaBanner(text: L("\(store.rosettaCount) extensions ship native code built only for Intel. They run through Rosetta today, which Apple is phasing out in a future macOS. Update them, or replace them with an Apple silicon build.",
                                      "\(store.rosettaCount) extension có mã native chỉ build cho Intel. Hiện chúng chạy nhờ Rosetta, mà Apple sẽ ngừng hỗ trợ ở một bản macOS tới. Hãy cập nhật hoặc thay bằng bản cho Apple silicon."))
            }
            content
        }
        .onAppear { if !store.scanned && !store.scanning { store.scan() } }
    }

    @ViewBuilder
    private var content: some View {
        if !store.scanned {
            ModuleEmptyState(symbol: "puzzlepiece.extension", title: L("Reading editor extensions…", "Đang đọc extension của editor…"),
                             message: L("VS Code, Cursor, Windsurf, VSCodium and JetBrains plugins.",
                                        "VS Code, Cursor, Windsurf, VSCodium và plugin JetBrains."),
                             busy: true)
                .card()
        } else if store.items.isEmpty {
            ModuleEmptyState(symbol: "puzzlepiece.extension", title: L("No editor extensions found", "Không tìm thấy extension nào"))
                .card()
        } else {
            table
        }
    }

    private var table: some View {
        let rows = store.visible(search: search)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 18)
                OverlineText(L("EXTENSION", "EXTENSION")).frame(maxWidth: .infinity, alignment: .leading)
                OverlineText(L("EDITOR", "EDITOR")).frame(width: 120, alignment: .leading)
                OverlineText(L("ARCHITECTURE", "KIẾN TRÚC")).frame(width: 150, alignment: .leading)
                OverlineText(L("SIZE", "DUNG LƯỢNG")).frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { e in row(e) }
                }
            }
        }
        .card()
    }

    private func row(_ e: EditorExtension) -> some View {
        HStack(alignment: .center, spacing: 12) {
            CheckboxView(state: store.checked.contains(e.id) ? .checked : .unchecked) { store.toggle(e) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
                    if !e.version.isEmpty {
                        Text(e.version).font(.system(size: 11.5)).foregroundStyle(DS.text3)
                    }
                }
                Text(e.identifier).font(DS.mono(11)).foregroundStyle(DS.text3).lineLimit(1)
                if !e.intelBinaries.isEmpty {
                    Text(L("Intel-only: ", "Chỉ Intel: ") + e.intelBinaries.joined(separator: ", "))
                        .font(DS.mono(10.5))
                        .foregroundStyle(DS.warning)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(e.editor).font(.system(size: 12.5)).foregroundStyle(DS.text2).lineLimit(1)
                .frame(width: 120, alignment: .leading)
            HStack(spacing: 6) {
                Chip(text: e.status.title, tint: tint(e.status))
                if e.status.needsRosetta {
                    Text("Rosetta").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.warning)
                }
            }
            .frame(width: 150, alignment: .leading)
            Text(Fmt.size(e.size)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(DS.text)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FileOps.reveal(e.url) }
        .contextMenu {
            Button(L("Show in Finder", "Mở trong Finder")) { FileOps.reveal(e.url) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(DS.rowDivider).frame(height: 1) }
    }

    private func tint(_ s: NativeStatus) -> Color {
        switch s {
        case .intelOnly: return Color(hex: 0xFFB8B8)
        case .mixed: return DS.warning
        case .universal, .appleSilicon: return DS.success
        case .noNative: return .white
        }
    }
}

/// Bottom bar for the Extensions tab.
@MainActor
struct ExtensionsActionBar: View {
    @Environment(AppModel.self) private var model
    private var store: ExtensionsStore { .shared }

    var body: some View {
        let n = store.checked.count
        ActionBar {
            SelectionSummary(
                title: n == 0 ? L("No extensions selected", "Chưa chọn extension nào")
                    : L("\(n == 1 ? "1 extension" : "\(n) extensions") selected · \(Fmt.size(store.selectedSize))",
                        "Đã chọn \(n) extension · \(Fmt.size(store.selectedSize))"),
                detail: L("\(store.items.count) extensions · \(store.rosettaCount) need Rosetta · removed ones go to the Trash; restart the editor afterwards",
                          "\(store.items.count) extension · \(store.rosettaCount) cần Rosetta · extension bị gỡ vào Thùng rác; khởi động lại editor sau đó"))
        } actions: {
            Toggle(L("Only Rosetta", "Chỉ mục cần Rosetta"), isOn: Binding(get: { store.onlyRosetta }, set: { store.onlyRosetta = $0 }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12.5))
            Button {
                store.scan()
            } label: {
                Label(L("Rescan", "Quét lại"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(OutlineButtonStyle(height: 36))
            .disabled(store.scanning)
            Button(L("Remove…", "Gỡ…")) { review() }
                .buttonStyle(FilledButtonStyle())
                .disabled(n == 0 || store.trashing)
        }
    }

    private func review() {
        let items = store.selected.map {
            ReviewItem(id: $0.id, title: "\($0.editor) · \($0.name)", detail: Paths.tilde($0.url), size: $0.size, method: .trash)
        }
        model.review = ReviewRequest(
            title: L("Remove Editor Extensions", "Gỡ extension của editor"),
            items: items,
            warnings: [L("Quit the editors first. They notice the missing extensions on their next start; you can reinstall any of them from the marketplace.",
                         "Hãy thoát editor trước. Editor sẽ nhận ra extension đã bị gỡ ở lần mở tiếp theo; bạn có thể cài lại từ marketplace.")],
            confirmLabel: L("Move to Trash", "Chuyển vào Thùng rác"),
            perform: {
                model.review = nil
                Task { @MainActor in
                    let out = await ExtensionsStore.shared.trashSelected()
                    model.addFreed(out.freed)
                    model.showToast(out.failures.isEmpty
                                    ? L("Moved \(out.moved.count) extensions to the Trash", "Đã chuyển \(out.moved.count) extension vào Thùng rác")
                                    : L("Moved \(out.moved.count) · failed: \(out.failures[0])", "Đã chuyển \(out.moved.count) · lỗi: \(out.failures[0])"))
                }
            })
    }
}

/// Warning strip about Rosetta going away.
struct RosettaBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cpu").font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.warning)
            Text(text).font(.system(size: 12.5)).foregroundStyle(DS.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.warning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.warning.opacity(0.3), lineWidth: 1))
    }
}
