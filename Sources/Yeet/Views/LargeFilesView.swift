import QuickLook
import SwiftUI

/// "Large & Old Files": big files in Home the user may have forgotten, filtered by kind and age.
struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var quickLookURL: URL? = nil

    private var store: LargeFilesStore { LargeFilesStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(Module.largeFiles.title,
                         subtitle: L("Big files in your Home folder you may have forgotten",
                                     "File lớn trong thư mục Home mà bạn có thể đã quên")) {
                if store.scanning {
                    Button(L("Stop", "Dừng")) { store.cancel() }
                        .buttonStyle(OutlineButtonStyle())
                } else {
                    Button {
                        store.scan()
                    } label: {
                        Label(L("Rescan", "Quét lại"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(store.trashing)
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.scanned && !store.scanning {
                actionBar
            }
        }
        .quickLookPreview($quickLookURL)
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        if store.scanning {
            VStack(spacing: 4) {
                Spacer()
                ModuleEmptyState(symbol: "magnifyingglass",
                                 title: L("Searching your Home folder…", "Đang tìm trong thư mục Home…"),
                                 busy: true,
                                 progress: L("\(Fmt.count(store.progress)) items checked",
                                             "Đã kiểm tra \(Fmt.count(store.progress)) mục"))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        } else if !store.scanned {
            VStack(spacing: 4) {
                Spacer()
                ModuleEmptyState(symbol: "doc.fill",
                                 title: Module.largeFiles.title,
                                 message: L("Find big files you forgot about: old downloads, videos, disk images and model checkpoints. App data, Photos and Music libraries, the Trash and iCloud-only files are never listed.",
                                            "Tìm các file lớn bạn đã quên: bản tải cũ, video, ảnh đĩa và checkpoint mô hình. Dữ liệu ứng dụng, thư viện Ảnh và Nhạc, Thùng rác và file chỉ có trên iCloud không bao giờ được liệt kê."))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    sizePicker.frame(width: 150)
                    Button(L("Scan", "Quét")) { store.scan() }
                        .buttonStyle(FilledButtonStyle())
                }
                Spacer()
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                LargeFilterPanel()
                    .frame(width: 210)
                LargeFileTable(quickLookURL: $quickLookURL)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var sizePicker: some View {
        Picker(L("Larger than", "Lớn hơn"), selection: Binding(get: { store.minSize },
                                                                 set: { store.setMinSize($0) })) {
            ForEach(LargeFilesStore.sizeOptions, id: \.self) { bytes in
                Text(LargeFilesStore.sizeLabel(bytes)).tag(bytes)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: Action bar

    private var actionBar: some View {
        let n = store.checked.count
        let hidden = store.hiddenSelectionCount
        return ActionBar {
            SelectionSummary(
                title: n == 0 ? L("No files selected", "Chưa chọn file nào")
                    : L("Selected \(n == 1 ? "1 file" : "\(n) files") · \(Fmt.size(store.selectedSize))",
                        "Đã chọn \(n) file · \(Fmt.size(store.selectedSize))"),
                detail: hidden > 0
                    ? L("\(hidden) selected \(hidden == 1 ? "file is" : "files are") hidden by the current filters",
                        "\(hidden) file đã chọn đang bị bộ lọc ẩn")
                    : L("Selected files go to the Trash; you can put them back", "File đã chọn sẽ vào Thùng rác, có thể khôi phục"))
        } actions: {
            Button(L("Deselect", "Bỏ chọn")) { store.checked.removeAll() }
                .buttonStyle(OutlineButtonStyle(height: 36))
                .disabled(n == 0)
            Button(L("Move to Trash", "Chuyển vào Thùng rác")) { requestTrash() }
                .buttonStyle(FilledButtonStyle())
                .disabled(n == 0 || store.trashing)
        }
    }

    private func requestTrash() {
        let targets = store.selectedFiles
        guard !targets.isEmpty else { return }
        let items = targets.map { f in
            ReviewItem(id: f.id, title: f.name, detail: Paths.tilde(f.url), size: f.size, method: .trash)
        }
        let model = self.model
        model.review = ReviewRequest(
            title: L("Move Large Files to Trash", "Chuyển file lớn vào Thùng rác"),
            items: items,
            confirmLabel: L("Move to Trash", "Chuyển vào Thùng rác"),
            perform: {
                model.review = nil
                Task { @MainActor in
                    let out = await LargeFilesStore.shared.trashSelected()
                    let n = out.moved.count
                    if out.failures.isEmpty {
                        model.showToast(L("Moved \(n == 1 ? "1 file" : "\(n) files") (\(Fmt.size(out.freed))) to the Trash",
                                          "Đã chuyển \(n) file (\(Fmt.size(out.freed))) vào Thùng rác"))
                    } else {
                        model.showToast(L("Moved \(n) · \(out.failures.count) failed: \(out.failures[0])",
                                          "Đã chuyển \(n) · \(out.failures.count) lỗi: \(out.failures[0])"),
                                        seconds: 5)
                    }
                }
            })
    }
}

// MARK: - Filter panel

private struct LargeFilterPanel: View {
    private var store: LargeFilesStore { LargeFilesStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                OverlineText(L("KIND", "LOẠI"))
                ForEach(FileKind.allCases) { kind in
                    kindRow(kind)
                }

                OverlineText(L("NOT OPENED SINCE", "CHƯA MỞ TỪ"))
                    .padding(.top, 10)
                ForEach(AgeFilter.allCases) { age in
                    ageRow(age)
                }

                OverlineText(L("LARGER THAN", "LỚN HƠN"))
                    .padding(.top, 10)
                Picker("", selection: Binding(get: { store.minSize }, set: { store.setMinSize($0) })) {
                    ForEach(LargeFilesStore.sizeOptions, id: \.self) { bytes in
                        Text(LargeFilesStore.sizeLabel(bytes)).tag(bytes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
    }

    private func kindRow(_ kind: FileKind) -> some View {
        let on = store.kindFilter.contains(kind)
        let s = store.stats(for: kind)
        return HStack(spacing: 8) {
            CheckboxView(state: on ? .checked : .unchecked) { store.toggleKind(kind) }
            Circle().fill(kind.color).frame(width: 7, height: 7)
            Text(kind.title)
                .font(.system(size: 12.5))
                .foregroundStyle(s.count > 0 ? DS.text : DS.text3)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(s.count > 0 ? Fmt.size(s.size) : "—")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(DS.text3)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.toggleKind(kind) }
    }

    private func ageRow(_ age: AgeFilter) -> some View {
        let on = store.ageFilter == age
        return Button {
            store.ageFilter = age
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(on ? DS.text : DS.text3)
                Text(age.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(on ? DS.text : DS.text2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - File table

private struct LargeFileTable: View {
    @Binding var quickLookURL: URL?
    @FocusState private var tableFocused: Bool

    private var store: LargeFilesStore { LargeFilesStore.shared }

    private let kindWidth: CGFloat = 92
    private let dateWidth: CGFloat = 110
    private let sizeWidth: CGFloat = 80

    var body: some View {
        let rows = store.visible
        let visibleSize = rows.reduce(Int64(0)) { $0 + $1.size }
        VStack(spacing: 0) {
            // Big total
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.size(visibleSize))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(DS.text)
                    .monospacedDigit()
                Text(L("in \(rows.count == 1 ? "1 file" : "\(Fmt.count(rows.count)) files") larger than \(LargeFilesStore.sizeLabel(store.minSize))",
                       "trong \(Fmt.count(rows.count)) file lớn hơn \(LargeFilesStore.sizeLabel(store.minSize))"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.text2)
                if store.partial {
                    Label(L("Scan stopped early; results are incomplete", "Đã dừng quét sớm; kết quả chưa đầy đủ"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.warning)
                } else if store.foundCount > store.files.count {
                    Text(L("Showing the \(Fmt.count(store.files.count)) largest of \(Fmt.count(store.foundCount)) files",
                           "Hiển thị \(Fmt.count(store.files.count)) file lớn nhất trong \(Fmt.count(store.foundCount)) file"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.text3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Column header
            HStack(spacing: 10) {
                Color.clear.frame(width: 18, height: 1)
                columnButton(L("NAME", "TÊN"), sort: .name)
                    .padding(.leading, 38)
                    .frame(maxWidth: .infinity, alignment: .leading)
                OverlineText(L("KIND", "LOẠI"))
                    .frame(width: kindWidth, alignment: .leading)
                columnButton(L("LAST OPENED", "MỞ LẦN CUỐI"), sort: .oldest)
                    .frame(width: dateWidth, alignment: .leading)
                columnButton(L("SIZE", "DUNG LƯỢNG"), sort: .size)
                    .frame(width: sizeWidth, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }

            if rows.isEmpty {
                ModuleEmptyState(symbol: "checkmark.circle",
                                 title: L("Nothing here", "Không có gì ở đây"),
                                 message: L("No files match the current filters.", "Không có file nào khớp bộ lọc hiện tại."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { f in
                            row(f)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Footer hint
            Text(L("Press Space for Quick Look; selected files go to the Trash",
                   "Nhấn Space để xem nhanh; file đã chọn sẽ vào Thùng rác"))
                .font(.system(size: 11.5))
                .foregroundStyle(DS.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .overlay(alignment: .top) { Rectangle().fill(DS.divider).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
        .focusable()
        .focused($tableFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let id = store.focused, let f = store.files.first(where: { $0.id == id }) else { return .ignored }
            quickLookURL = (quickLookURL == f.url) ? nil : f.url
            return .handled
        }
    }

    private func columnButton(_ title: String, sort: LargeSort) -> some View {
        let active = store.sort == sort
        return Button {
            store.sort = sort
        } label: {
            HStack(spacing: 3) {
                OverlineText(title)
                if active {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.text2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ f: LargeFile) -> some View {
        let isFocused = store.focused == f.id
        let isChecked = store.checked.contains(f.id)
        return HStack(spacing: 10) {
            CheckboxView(state: isChecked ? .checked : .unchecked) { store.toggle(f) }
            HueTile(symbol: f.kind.symbol, color: f.kind.color, size: 28, glyph: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(f.location)
                    .font(DS.mono(11))
                    .foregroundStyle(DS.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(f.kind.label)
                .font(.system(size: 12))
                .foregroundStyle(DS.text2)
                .lineLimit(1)
                .frame(width: kindWidth, alignment: .leading)
            Text(Fmt.modified(f.lastUsed))
                .font(.system(size: 12))
                .foregroundStyle(f.isOld ? DS.warning : DS.text2)
                .lineLimit(1)
                .frame(width: dateWidth, alignment: .leading)
            Text(Fmt.size(f.size))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DS.text)
                .frame(width: sizeWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isFocused ? DS.surfaceStrong : Color.clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FileOps.reveal(f.url) }
        .onTapGesture {
            store.focused = f.id
            tableFocused = true
            if quickLookURL != nil { quickLookURL = f.url }
        }
        .help(L("Double-click to reveal in Finder", "Nhấp đúp để hiện trong Finder"))
        .contextMenu {
            Button(L("Reveal in Finder", "Hiện trong Finder")) { FileOps.reveal(f.url) }
            Button(L("Quick Look", "Xem nhanh")) { quickLookURL = f.url }
        }
    }
}
