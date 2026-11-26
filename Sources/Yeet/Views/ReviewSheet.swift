import SwiftUI

/// "Review before cleaning": what will happen to each selected item, grouped by method
/// (deleted permanently vs. moved to the Trash), with blocking warnings on top.
struct ReviewSheet: View {
    let request: ReviewRequest
    let dismiss: () -> Void
    @Environment(\.hue) private var hue

    private struct Group: Identifiable {
        let method: CleanMethod
        let items: [ReviewItem]
        var id: Int { method.rawValue }
        var total: Int64 { items.reduce(Int64(0)) { $0 + $1.size } }
    }

    private var groups: [Group] {
        CleanMethod.allCases.compactMap { m -> Group? in
            let items = request.items.filter { $0.method == m }.sorted { $0.size > $1.size }
            return items.isEmpty ? nil : Group(method: m, items: items)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hue.tile)
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "checklist").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.title).font(.system(size: 18, weight: .bold)).foregroundStyle(DS.text)
                        Text(L("\(request.items.count == 1 ? "1 item" : "\(request.items.count) items") · \(Fmt.size(request.total)). Yeet works through them in this order and stops at the first error it can’t skip.",
                               "\(request.items.count) mục · \(Fmt.size(request.total)). Yeet làm theo thứ tự dưới đây và bỏ qua mục bị lỗi."))
                            .font(.system(size: 13))
                            .foregroundStyle(DS.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Totals per method
                HStack(spacing: 1) {
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.method.title).font(.system(size: 12)).foregroundStyle(DS.text2)
                            Text(Fmt.size(g.total))
                                .font(.system(size: 18, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(DS.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(DS.sheet)
                    }
                }
                .background(DS.divider)
                .overlay(alignment: .top) { Rectangle().fill(DS.divider).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(request.warnings, id: \.self) { w in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14))
                                Text(w).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(DS.warning)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.warning.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.warning.opacity(0.3), lineWidth: 1))
                        }

                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, g in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(g.method.color))
                                    Text(g.method.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(DS.text)
                                    Text(g.method.hint).font(.system(size: 12)).foregroundStyle(DS.text3)
                                }
                                VStack(spacing: 0) {
                                    ForEach(g.items) { item in
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundStyle(DS.text)
                                                    .lineLimit(1)
                                                Text(item.detail)
                                                    .font(DS.mono(11.5))
                                                    .foregroundStyle(DS.text2)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                            Spacer(minLength: 8)
                                            Text(Fmt.size(item.size))
                                                .font(.system(size: 13, weight: .semibold))
                                                .monospacedDigit()
                                                .foregroundStyle(DS.text)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .overlay(alignment: .bottom) { Rectangle().fill(DS.rowDivider).frame(height: 1) }
                                    }
                                }
                                .card(radius: 12)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .frame(maxHeight: 420)

                HStack(spacing: 10) {
                    Spacer()
                    Button(L("Cancel", "Huỷ"), action: dismiss)
                        .buttonStyle(OutlineButtonStyle(height: 36, horizontalPadding: 16))
                        .keyboardShortcut(.cancelAction)
                    Button(request.confirmLabel ?? L("Clean \(Fmt.size(request.total))", "Dọn \(Fmt.size(request.total))")) {
                        request.perform()
                    }
                    .buttonStyle(FilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.18))
                .overlay(alignment: .top) { Rectangle().fill(DS.divider).frame(height: 1) }
            }
            .frame(width: 640)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.sheet))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 24)
            .onExitCommand(perform: dismiss)
            .accessibilityAddTraits(.isModal)
        }
    }
}
