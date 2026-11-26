import SwiftUI

/// "System Health": battery, storage, thermal state and system information.
/// Logic ported from MacSweep (see Core/Health.swift). The parent paints the window background.
struct HealthView: View {
    private var store: HealthStore { HealthStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(Module.health.title,
                         subtitle: L("Battery, storage and system, straight from macOS",
                                     "Pin, ổ đĩa và hệ thống, đọc trực tiếp từ macOS")) {
                Button {
                    store.refresh()
                } label: {
                    HStack(spacing: 6) {
                        SpinningIcon(systemName: "arrow.clockwise", active: store.isRefreshing)
                        Text(store.isRefreshing ? L("Reading…", "Đang đọc…") : L("Refresh", "Làm mới"))
                    }
                }
                .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 13, horizontalPadding: 12))
                .disabled(store.isRefreshing)
            }

            if !store.loaded {
                ModuleEmptyState(symbol: Module.health.symbol,
                                 title: L("Reading battery, storage and system information…",
                                          "Đang đọc thông tin pin, ổ đĩa và hệ thống…"),
                                 busy: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Two columns; cards in a row share the taller card's height.
                        HStack(alignment: .top, spacing: 16) {
                            BatteryCard(battery: store.battery)
                            StorageCard(storage: store.storage)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 16) {
                            ThermalCard(state: store.thermal)
                            SystemCard(system: store.system)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Text(L("Every value is read from macOS itself (the I/O Registry, power sources and sysctl). Nothing is estimated unless marked, and nothing leaves your Mac.",
                               "Mọi số liệu đều đọc từ chính macOS (I/O Registry, nguồn điện và sysctl). Không ước tính trừ khi có ghi chú, và không gửi dữ liệu ra khỏi máy."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(DS.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { if !store.loaded { store.refresh() } }
    }
}

// MARK: - Shared pieces

private func notAvailable() -> String { L("Not available", "Không có") }

/// Tile + title + subtitle, with an optional trailing view (a condition chip).
private struct CardTitle<Trailing: View>: View {
    let symbol: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            HueTile(symbol: symbol, color: color, size: 34, glyph: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.text)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(DS.text2).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    init(symbol: String, color: Color, title: String, subtitle: String? = nil) {
        self.init(symbol: symbol, color: color, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Thin rounded progress bar.
private struct HealthBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.diskTrack)
                Capsule().fill(color)
                    .frame(width: CGFloat(max(0, min(1, fraction))) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

/// Big figure with a caption next to it ("90%  Maximum capacity").
private struct BigFigure: View {
    let value: String
    let title: String
    let caption: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value)
                .font(.system(size: 38, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DS.text)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(DS.text)
                Text(caption).font(.system(size: 12)).foregroundStyle(DS.text3)
            }
        }
    }
}

private struct KeyValueRows: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    Text(rows[i].0)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.text2)
                        .gridColumnAlignment(.leading)
                    Text(rows[i].1)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct Note: View {
    let text: String
    var symbol = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12.5))
            Text(text)
                .font(.system(size: 12))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DS.text3)
    }
}

// MARK: - Battery

private struct BatteryCard: View {
    let battery: Battery?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let b = battery {
                CardTitle(symbol: b.charging ? "battery.100.bolt" : "battery.75",
                          color: DS.success,
                          title: L("Battery", "Pin"),
                          subtitle: L("Health as macOS reports it", "Tình trạng theo macOS")) {
                    HStack(spacing: 6) {
                        Text(L("Condition", "Tình trạng")).font(.system(size: 12)).foregroundStyle(DS.text3)
                        Chip(text: b.conditionLabel, tint: conditionTint(b.condition))
                            .help(b.conditionDetail ?? "")
                    }
                }

                BigFigure(value: b.maxCapacityPct.map { "\($0)%" } ?? "—",
                          title: L("Maximum capacity", "Dung lượng tối đa"),
                          caption: L("compared with when it was new", "so với khi còn mới"))
                if let pct = b.maxCapacityPct {
                    HealthBar(fraction: Double(pct) / 100, color: pct >= 80 ? DS.success : DS.warning)
                }

                KeyValueRows(rows: rows(b))

                Note(text: b.maxCapacityIsEstimate
                     ? L("Maximum capacity here is full-charge capacity divided by design capacity. Apple calculates its own figure (System Settings › Battery) its own way, so it may differ by a point or two.",
                         "Dung lượng tối đa ở đây là dung lượng sạc đầy chia cho dung lượng thiết kế. Apple tính con số của mình (Cài đặt hệ thống › Pin) theo cách riêng, nên có thể lệch một vài điểm.")
                     : L("Maximum capacity is Apple's own figure. Apple calculates it its own way, so it won't exactly match the mAh ratio above.",
                         "Dung lượng tối đa là con số của Apple. Apple tính theo cách riêng, nên sẽ không khớp hẳn với tỉ lệ mAh ở trên."))
            } else {
                CardTitle(symbol: "powerplug", color: Color.white.opacity(0.35),
                          title: L("Battery", "Pin"),
                          subtitle: L("This Mac has no battery.", "Máy Mac này không có pin."))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func conditionTint(_ c: Battery.Condition) -> Color {
        switch c {
        case .normal: return DS.success
        case .service: return DS.warning
        case .unknown: return .white
        }
    }

    private func rows(_ b: Battery) -> [(String, String)] {
        var out: [(String, String)] = []

        let cycles: String
        switch (b.cycles, b.designCycles) {
        case let (c?, d?): cycles = L("\(Fmt.count(c)) of \(Fmt.count(d))", "\(Fmt.count(c)) / \(Fmt.count(d))")
        case (let c?, nil): cycles = Fmt.count(c)
        default: cycles = notAvailable()
        }
        out.append((L("Charge cycles", "Số chu kỳ sạc"), cycles))

        let charge: String
        if let c = b.chargePct {
            if b.charging {
                charge = L("\(c)% · charging", "\(c)% · đang sạc")
            } else if b.pluggedIn {
                charge = L("\(c)% · plugged in, not charging", "\(c)% · đang cắm sạc, không sạc")
            } else {
                charge = L("\(c)% · on battery", "\(c)% · đang dùng pin")
            }
        } else {
            charge = notAvailable()
        }
        out.append((L("Charge now", "Mức pin hiện tại"), charge))

        out.append((L("Design capacity", "Dung lượng thiết kế"), b.designMAh.map(HealthFmt.mAh) ?? notAvailable()))

        let full: String
        switch (b.nominalMAh, b.rawMaxMAh) {
        case let (n?, r?) where n != r:
            full = L("\(HealthFmt.mAh(n)) (raw reading \(HealthFmt.mAh(r)))", "\(HealthFmt.mAh(n)) (số đo thô \(HealthFmt.mAh(r)))")
        case let (n?, _): full = HealthFmt.mAh(n)
        case (nil, let r?): full = HealthFmt.mAh(r)
        default: full = notAvailable()
        }
        out.append((L("Full-charge capacity", "Dung lượng sạc đầy"), full))

        let temp = b.temperatureC.map { String(format: "%.1f °C", $0) } ?? notAvailable()
        out.append((L("Temperature", "Nhiệt độ"), temp))
        return out
    }
}

// MARK: - Storage

private struct StorageCard: View {
    let storage: Storage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = storage {
                CardTitle(symbol: "internaldrive.fill", color: DS.folder,
                          title: L("Storage", "Ổ đĩa"),
                          subtitle: subtitle(s))
                BigFigure(value: Fmt.size(s.free),
                          title: L("free", "còn trống"),
                          caption: L("of \(Fmt.capacity(s.total))", "trên tổng \(Fmt.capacity(s.total))"))
                HealthBar(fraction: s.usedFraction, color: barColor(s))
                KeyValueRows(rows: [
                    (L("Volume", "Phân vùng"), s.volumeName ?? notAvailable()),
                    (L("Drive", "Ổ cứng"), driveText(s)),
                    (L("Capacity", "Dung lượng"), Fmt.capacity(s.total)),
                    (L("Used", "Đã dùng"), "\(Fmt.size(s.used)) · \(Int((s.usedFraction * 100).rounded()))%"),
                    (L("Free", "Còn trống"), Fmt.size(s.free)),
                ])
            } else {
                CardTitle(symbol: "internaldrive.fill", color: DS.folder,
                          title: L("Storage", "Ổ đĩa"),
                          subtitle: L("macOS didn't report the startup disk.", "macOS không báo thông tin ổ khởi động."))
            }
            Note(text: L("Drive wear (lifespan used, data written, power-on hours) comes from the SSD's SMART log, which App Store apps can't read because they run in a sandbox. Use a non-sandboxed tool such as smartctl to see it.",
                         "Độ hao mòn ổ (tuổi thọ đã dùng, dữ liệu đã ghi, số giờ hoạt động) nằm trong nhật ký SMART của SSD, mà ứng dụng App Store không đọc được vì chạy trong sandbox. Hãy dùng công cụ ngoài sandbox như smartctl để xem."),
                 symbol: "lock.shield")
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func subtitle(_ s: Storage) -> String {
        [s.volumeName, s.model].compactMap { $0 }.joined(separator: " · ")
    }

    private func driveText(_ s: Storage) -> String {
        let kind: String? = s.isSSD.map { $0 ? L("SSD", "SSD") : L("Hard disk", "Ổ cứng HDD") }
        let parts = [s.model, kind].compactMap { $0 }
        return parts.isEmpty ? notAvailable() : parts.joined(separator: " · ")
    }

    private func barColor(_ s: Storage) -> Color {
        if s.usedFraction >= 0.95 { return DS.danger }
        if s.usedFraction >= 0.85 { return DS.warning }
        return DS.success
    }
}

// MARK: - Thermal

private struct ThermalCard: View {
    let state: ProcessInfo.ThermalState

    private var color: Color {
        switch state {
        case .nominal: return DS.success
        case .fair: return DS.warning
        case .serious, .critical: return DS.danger
        @unknown default: return DS.text2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(symbol: "thermometer.medium", color: color, title: L("Thermal", "Nhiệt độ máy"))
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(HealthStore.label(for: state))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Note(text: L("macOS's thermal state: whether it's slowing the Mac down to cool it. Updates live.",
                         "Trạng thái nhiệt của macOS: máy có đang bị giảm tốc để hạ nhiệt hay không. Tự cập nhật."))
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

// MARK: - System

private struct SystemCard: View {
    let system: SystemInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(symbol: "cpu", color: Hue.indigo.tileDark, title: L("System", "Hệ thống"))
            if let s = system {
                KeyValueRows(rows: rows(s))
            } else {
                Text(notAvailable()).font(.system(size: 13)).foregroundStyle(DS.text2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func rows(_ s: SystemInfo) -> [(String, String)] {
        let model: String
        switch (s.modelName, s.modelID) {
        case let (n?, id?): model = "\(n) (\(id))"
        case (let n?, nil): model = n
        case (nil, let id?): model = id
        default: model = notAvailable()
        }
        let os = s.osBuild.map { "macOS \(s.osVersion) (\($0))" } ?? "macOS \(s.osVersion)"
        return [
            (L("Model", "Kiểu máy"), model),
            (L("Chip", "Chip"), s.chip ?? notAvailable()),
            (L("Memory", "Bộ nhớ"), s.memoryBytes > 0 ? HealthFmt.memory(s.memoryBytes) : notAvailable()),
            (L("macOS", "macOS"), os),
            (L("Up since restart", "Thời gian chạy"), s.uptime.map(HealthFmt.uptime) ?? notAvailable()),
        ]
    }
}
