import SwiftUI

/// "Duplicates": identical copies (matched by content) in the visible folders of Home.
/// One copy of every group is always kept.
@MainActor
struct DuplicatesView: View {
    @Environment(AppModel.self) private var model

    private var store: DuplicatesStore { DuplicatesStore.shared }

    var body: some View {
        let keepOptions: [(value: KeepRule, label: String)] = [
            (.oldest, L("Keep: Oldest", "Giữ: Cũ nhất")),
            (.newest, L("Keep: Newest", "Giữ: Mới nhất")),
        ]

        VStack(spacing: 0) {
            ModuleHeader(Module.duplicates.title,
                         subtitle: L("Identical files in Desktop, Documents, Downloads, Pictures, Movies and Music",
                                     "File giống hệt nhau trong Desktop, Documents, Downloads, Pictures, Movies và Music")) {
                SegmentedPill(selection: Binding(get: { store.keep }, set: { store.keep = $0 }),
                              options: keepOptions)
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

            if store.scanned && !store.scanning && !store.groups.isEmpty {
                actionBar
            }
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        if store.scanning {
            VStack(spacing: 4) {
                Spacer()
                ModuleEmptyState(symbol: "square.on.square",
                                 title: store.stage == 0
                                     ? L("Listing your files…", "Đang liệt kê file…")
                                     : L("Comparing contents…", "Đang so sánh nội dung…"),
                                 busy: true,
                                 progress: store.stage == 0
                                     ? L("\(Fmt.count(store.progress)) files checked", "Đã kiểm tra \(Fmt.count(store.progress)) file")
                                     : L("\(Fmt.count(store.progress)) files compared", "Đã so sánh \(Fmt.count(store.progress)) file"))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        } else if !store.scanned {
            VStack(spacing: 4) {
                Spacer()
                ModuleEmptyState(symbol: Module.duplicates.symbol,
                                 title: Module.duplicates.title,
                                 message: L("Find identical copies of files in Desktop, Documents, Downloads, Pictures, Movies and Music. Files are matched by content, not by name, and one copy is always kept. Photos and Music libraries, app data and iCloud-only files are never touched.",
                                            "Tìm các bản sao giống hệt nhau trong Desktop, Documents, Downloads, Pictures, Movies và Music. File được so khớp theo nội dung, không theo tên, và luôn giữ lại một bản. Thư viện Ảnh và Nhạc, dữ liệu ứng dụng và file chỉ có trên iCloud không bao giờ bị động đến."))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Picker(L("Larger than", "Lớn hơn"), selection: Binding(get: { store.minSize }, set: { store.minSize = $0 })) {
                        ForEach(DuplicatesStore.sizeOptions, id: \.self) { bytes in
                            Text(Self.minLabel(bytes)).tag(bytes)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    Button(L("Scan", "Quét")) { store.scan() }
                        .buttonStyle(FilledButtonStyle())
                }
                Spacer()
            }
        } else if store.groups.isEmpty {
            ModuleEmptyState(symbol: "checkmark.circle",
                             title: L("No duplicates found", "Không tìm thấy file trùng"),
                             message: store.partial
                                 ? L("The scan was stopped early, so results are incomplete.", "Đã dừng quét sớm nên kết quả chưa đầy đủ.")
                                 : L("Every file in your folders is unique.", "Mọi file trong các thư mục của bạn đều là duy nhất."))
        } else {
            HStack(alignment: .top, spacing: 16) {
                DupGroupList()
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)
                DupDetail()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    static func minLabel(_ bytes: Int64) -> String {
        bytes >= 1024 * 1024 ? "\(bytes / (1024 * 1024)) MB" : "\(bytes / 1024) KB"
    }

    // MARK: Action bar

    private var actionBar: some View {
        let n = store.selectedCount
        return ActionBar {
            SelectionSummary(
                title: n == 0 ? L("No copies selected", "Chưa chọn bản sao nào")
                    : L("Selected \(n == 1 ? "1 copy" : "\(n) copies") · \(Fmt.size(store.selectedSize))",
                        "Đã chọn \(n) bản sao · \(Fmt.size(store.selectedSize))"),
                detail: L("\(Fmt.size(store.total)) in \(store.extraCopies == 1 ? "1 extra copy" : "\(Fmt.count(store.extraCopies)) extra copies") · one copy is always kept",
                          "\(Fmt.size(store.total)) trong \(Fmt.count(store.extraCopies)) bản sao thừa · luôn giữ lại một bản"))
        } actions: {
            if n > 0 {
                Button(L("Deselect", "Bỏ chọn")) { store.deselectAll() }
                    .buttonStyle(OutlineButtonStyle(height: 36))
            }
            Button(L("Select all extra copies", "Chọn mọi bản sao thừa")) { store.selectAllExtraCopies() }
                .buttonStyle(OutlineButtonStyle(height: 36))
            Button(L("Move to Trash", "Chuyển vào Thùng rác")) { requestTrash() }
                .buttonStyle(FilledButtonStyle())
                .disabled(n == 0 || store.trashing)
        }
    }

    private func requestTrash() {
        var items: [ReviewItem] = []
        for g in store.groups {
            for f in g.files where store.checked.contains(f.id) {
                items.append(ReviewItem(id: f.id, title: f.name, detail: Paths.tilde(f.url), size: g.size, method: .trash))
            }
        }
        guard !items.isEmpty else { return }
        let model = self.model
        model.review = ReviewRequest(
            title: L("Move Duplicates to Trash", "Chuyển file trùng vào Thùng rác"),
            items: items,
            confirmLabel: L("Move to Trash", "Chuyển vào Thùng rác"),
            perform: {
                model.review = nil
                Task { @MainActor in
                    let out = await DuplicatesStore.shared.trashSelected()
                    let n = out.moved.count
                    if out.failures.isEmpty {
                        model.showToast(L("Moved \(n == 1 ? "1 copy" : "\(n) copies") (\(Fmt.size(out.freed))) to the Trash",
                                          "Đã chuyển \(n) bản sao (\(Fmt.size(out.freed))) vào Thùng rác"))
                    } else {
                        model.showToast(L("Moved \(n) · \(out.failures[0])", "Đã chuyển \(n) · \(out.failures[0])"),
                                        seconds: 5)
                    }
                }
            })
    }
}

// MARK: - Group list

@MainActor
private struct DupGroupList: View {
    private var store: DuplicatesStore { DuplicatesStore.shared }

    var body: some View {
        let focusedID = store.focused?.id
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.size(store.total))
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
                Text(L("wasted in \(store.groups.count == 1 ? "1 group" : "\(Fmt.count(store.groups.count)) groups")",
                       "lãng phí trong \(Fmt.count(store.groups.count)) nhóm"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.text2)
                if store.partial {
                    Label(L("Scan stopped early; results are incomplete", "Đã dừng quét sớm; kết quả chưa đầy đủ"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.groups) { g in
                        groupRow(g, focused: g.id == focusedID)
                    }
                }
                .padding(8)
            }
        }
        .frame(maxHeight: .infinity)
        .card()
    }

    private func groupRow(_ g: DupGroup, focused: Bool) -> some View {
        HStack(spacing: 10) {
            CheckboxView(state: store.checkState(g)) { store.toggleGroup(g) }
            HueTile(symbol: g.kind.symbol, color: g.kind.color, size: 28, glyph: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L("\(g.files.count) copies · \(Fmt.size(g.size)) each", "\(g.files.count) bản · mỗi bản \(Fmt.size(g.size))"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.size(g.wasted))
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DS.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(focused ? DS.surfaceStrong : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { store.focusedGroup = g.id }
    }
}

// MARK: - Detail

@MainActor
private struct DupDetail: View {
    @Environment(AppModel.self) private var model
    private var store: DuplicatesStore { DuplicatesStore.shared }

    var body: some View {
        Group {
            if let g = store.focused {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        HueTile(symbol: g.kind.symbol, color: g.kind.color, size: 36, glyph: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DS.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(L("\(g.files.count) identical copies · \(Fmt.size(g.size)) each · \(Fmt.size(g.wasted)) wasted",
                                   "\(g.files.count) bản giống hệt · mỗi bản \(Fmt.size(g.size)) · lãng phí \(Fmt.size(g.wasted))"))
                                .font(.system(size: 12))
                                .foregroundStyle(DS.text2)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button(L("Keep \(store.keep == .oldest ? "oldest" : "newest") only",
                                 "Chỉ giữ bản \(store.keep == .oldest ? "cũ nhất" : "mới nhất")")) {
                            store.selectGroup(g)
                        }
                        .buttonStyle(OutlineButtonStyle(height: 30, fontSize: 12.5, horizontalPadding: 12))
                    }
                    .padding(16)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(g.files) { f in
                                copyRow(f, in: g)
                                Rectangle().fill(DS.rowDivider).frame(height: 1)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }

                    Text(L("Files are matched by content. At least one copy of every group is always kept.",
                           "File được so khớp theo nội dung. Mỗi nhóm luôn giữ lại ít nhất một bản."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .overlay(alignment: .top) { Rectangle().fill(DS.divider).frame(height: 1) }
                }
            } else {
                ModuleEmptyState(symbol: "square.on.square", title: L("Select a group", "Chọn một nhóm"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    private func copyRow(_ f: DupFile, in g: DupGroup) -> some View {
        let removing = store.checked.contains(f.id)
        let isKeeper = store.keeper(g)?.id == f.id
        return HStack(spacing: 10) {
            Button {
                if !store.toggle(f, in: g) {
                    model.showToast(L("At least one copy is always kept", "Luôn giữ lại ít nhất một bản"))
                }
            } label: {
                Chip(text: removing ? L("Remove", "Xoá") : L("Keep", "Giữ"),
                     tint: removing ? DS.danger : DS.success)
                    .frame(width: 70, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(removing ? L("Click to keep this copy", "Bấm để giữ bản này")
                           : L("Click to remove this copy", "Bấm để xoá bản này"))

            VStack(alignment: .leading, spacing: 2) {
                Text(Paths.tilde(f.url))
                    .font(DS.mono(12))
                    .foregroundStyle(removing ? DS.text2 : DS.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(L("Modified \(Fmt.modified(f.modified))", "Sửa đổi \(Fmt.modified(f.modified))"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.text3)
                    if isKeeper {
                        Text(store.keep == .oldest ? L("· oldest", "· cũ nhất") : L("· newest", "· mới nhất"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(DS.text3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                FileOps.reveal(f.url)
            } label: {
                Label(L("Reveal", "Hiện"), systemImage: "magnifyingglass")
            }
            .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12, horizontalPadding: 10))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FileOps.reveal(f.url) }
    }
}
