// Mac Health: battery, storage, thermal state and system information.
//
// Logic ported from MacSweep (https://github.com/nihal4/macsweep), MIT License, Copyright (c) 2026 S. M. Nihal Ahmed.
//
// MacSweep shells out to system_profiler / ioreg and reads the NVMe SMART log. The App Store
// build runs in the App Sandbox (no Process, no IOKit user clients), so every value here is read
// directly: the battery from the I/O Registry (AppleSmartBattery) and IOPowerSources, storage
// from URL resource values plus the IOBlockStorageDevice registry entry, the rest from sysctl and
// ProcessInfo. Anything macOS doesn't report stays nil and is shown as "Not available".

import Foundation
import IOKit
import IOKit.ps
import Observation

// MARK: - Readings

struct Battery: Sendable, Equatable {
    enum Condition: Sendable, Equatable {
        case normal
        case service
        case unknown
    }

    /// "Maximum Capacity" in %. Apple's own figure when macOS exposes it to the sandbox,
    /// otherwise full-charge capacity / design capacity (`maxCapacityIsEstimate`).
    var maxCapacityPct: Int?
    var maxCapacityIsEstimate = true
    var condition: Condition = .unknown
    /// macOS's raw wording when it flags a problem (e.g. "Check Battery").
    var conditionDetail: String?
    var cycles: Int?
    /// Cycles the battery is designed for (DesignCycleCount9C, from the battery itself).
    var designCycles: Int?
    /// Current charge, %.
    var chargePct: Int?
    var charging = false
    var pluggedIn = false
    /// Raw readings, mAh.
    var designMAh: Int?
    var nominalMAh: Int?
    var rawMaxMAh: Int?
    var temperatureC: Double?

    var conditionLabel: String {
        switch condition {
        case .normal: return L("Normal", "Bình thường")
        case .service: return L("Service Recommended", "Nên thay pin")
        case .unknown: return L("Unknown", "Không rõ")
        }
    }
}

struct Storage: Sendable, Equatable {
    /// Volume name, e.g. "Macintosh HD".
    var volumeName: String?
    /// Drive model from the I/O Registry, e.g. "APPLE SSD AP0256Q".
    var model: String?
    /// True for solid-state media, nil when the registry doesn't say.
    var isSSD: Bool?
    var total: Int64 = 0
    var free: Int64 = 0

    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? min(1, max(0, Double(used) / Double(total))) : 0 }
    var freeFraction: Double { total > 0 ? min(1, max(0, Double(free) / Double(total))) : 1 }
}

struct SystemInfo: Sendable, Equatable {
    /// "MacBookAir10,1"
    var modelID: String?
    /// "MacBook Air (M2, 2022)" on Apple silicon, when the device tree has it.
    var modelName: String?
    /// "Apple M1"
    var chip: String?
    var memoryBytes: UInt64 = 0
    /// "14.5"
    var osVersion: String = ""
    /// "23F79"
    var osBuild: String?
    var bootDate: Date?

    var uptime: TimeInterval? { bootDate.map { max(0, Date().timeIntervalSince($0)) } }
}

// MARK: - Store

@Observable
final class HealthStore {
    static let shared = HealthStore()

    /// nil on Macs without a battery (desktops).
    var battery: Battery?
    var storage: Storage?
    var system: SystemInfo?
    var thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    /// True once the first refresh finished.
    var loaded = false
    var isRefreshing = false

    @ObservationIgnored private var thermalObserver: NSObjectProtocol?

    init() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            Task { @MainActor in self?.thermal = state }
        }
    }

    /// Reads everything off the main thread, then publishes on the main actor.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> (Battery?, Storage?, SystemInfo) in
                (HealthReader.battery(), HealthReader.storage(), HealthReader.system())
            }.value
            battery = result.0
            storage = result.1
            system = result.2
            thermal = ProcessInfo.processInfo.thermalState
            loaded = true
            isRefreshing = false
        }
    }

    // MARK: Summaries (Overview card)

    /// "90% capacity", nil without a battery.
    var batterySummary: String? {
        guard let b = battery else { return nil }
        if let pct = b.maxCapacityPct { return L("\(pct)% capacity", "Dung lượng \(pct)%") }
        return b.conditionLabel
    }

    var thermalLabel: String { HealthStore.label(for: thermal) }

    /// No battery service warning, not running hot, and at least 5% of the disk free.
    var overallOK: Bool {
        if battery?.condition == .service { return false }
        if thermal == .serious || thermal == .critical { return false }
        if let s = storage, s.total > 0, s.freeFraction < 0.05 { return false }
        return true
    }

    static func label(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return L("Normal", "Bình thường")
        case .fair: return L("Warm", "Hơi ấm")
        case .serious: return L("Hot: performance reduced", "Nóng: hiệu năng bị giảm")
        case .critical: return L("Critical: performance heavily reduced", "Rất nóng: hiệu năng giảm mạnh")
        @unknown default: return L("Unknown", "Không rõ")
        }
    }
}

// MARK: - Formatting

enum HealthFmt {
    /// `42 min`, `3 h 5 min`, `2 d 4 h`
    static func uptime(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let d = s / 86_400, h = s % 86_400 / 3_600, m = s % 3_600 / 60
        if d == 0 && h == 0 { return L("\(m) min", "\(m) phút") }
        if d == 0 { return L("\(h) h \(m) min", "\(h) giờ \(m) phút") }
        return L("\(d) d \(h) h", "\(d) ngày \(h) giờ")
    }

    /// `4,382 mAh`
    static func mAh(_ v: Int) -> String { "\(Fmt.count(v)) mAh" }

    /// `8 GB` (binary, like About This Mac).
    static func memory(_ bytes: UInt64) -> String {
        "\(Int((Double(bytes) / 1_073_741_824).rounded())) GB"
    }
}

// MARK: - Reading (any thread)

enum HealthReader {
    // MARK: Battery

    static func battery() -> Battery? {
        let reg = registryProperties(serviceClass: "AppleSmartBattery")
        let ps = internalPowerSource()
        if reg == nil && ps == nil { return nil }
        if let reg, (reg["BatteryInstalled"] as? NSNumber)?.boolValue == false { return nil }

        var b = Battery()
        let d = reg ?? [:]
        let data = d["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? {
            (d[key] as? NSNumber)?.intValue ?? (data[key] as? NSNumber)?.intValue
        }
        func flag(_ key: String) -> Bool { (d[key] as? NSNumber)?.boolValue ?? false }

        b.cycles = int("CycleCount")
        b.designCycles = int("DesignCycleCount9C")
        b.designMAh = int("DesignCapacity")
        b.nominalMAh = int("NominalChargeCapacity")
        b.rawMaxMAh = int("AppleRawMaxCapacity")
        b.charging = flag("IsCharging")
        b.pluggedIn = flag("ExternalConnected")
        // Centi-degrees Celsius (Intel Macs; most Apple silicon Macs don't publish it).
        if let t = int("Temperature"), t > 0 { b.temperatureC = Double(t) / 100 }

        // Current charge: % on Apple silicon, mAh/mAh on Intel; the ratio works for both.
        if let cur = (d["CurrentCapacity"] as? NSNumber)?.intValue,
           let top = (d["MaxCapacity"] as? NSNumber)?.intValue, top > 0 {
            b.chargePct = min(100, Int((Double(cur) / Double(top) * 100).rounded()))
        }

        var healthWord: String?
        if let ps {
            if let cur = (ps["Current Capacity"] as? NSNumber)?.intValue,
               let top = (ps["Max Capacity"] as? NSNumber)?.intValue, top > 0 {
                b.chargePct = min(100, Int((Double(cur) / Double(top) * 100).rounded()))
            }
            if let charging = (ps["Is Charging"] as? NSNumber)?.boolValue { b.charging = charging }
            if let state = ps["Power Source State"] as? String { b.pluggedIn = b.pluggedIn || state == "AC Power" }
            if let pct = (ps["Maximum Capacity Percent"] as? NSNumber)?.intValue, (1...100).contains(pct) {
                b.maxCapacityPct = pct
                b.maxCapacityIsEstimate = false
            }
            healthWord = ps["BatteryHealth"] as? String
            if let c = ps["BatteryHealthCondition"] as? String, !c.isEmpty { b.conditionDetail = c }
        }

        if b.maxCapacityPct == nil, let design = b.designMAh, design > 0, let full = b.nominalMAh ?? b.rawMaxMAh {
            b.maxCapacityPct = min(100, Int((Double(full) / Double(design) * 100).rounded()))
            b.maxCapacityIsEstimate = true
        }

        let permanentFailure = int("PermanentFailureStatus") ?? 0
        if permanentFailure != 0 || b.conditionDetail != nil {
            b.condition = .service
        } else if let w = healthWord {
            b.condition = (w == "Good") ? .normal : .service
            if w != "Good" { b.conditionDetail = w }
        } else if reg != nil {
            b.condition = .normal
        }
        return b
    }

    /// The internal battery's IOPowerSources description.
    private static func internalPowerSource() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() else { return nil }
        for item in list as NSArray {
            let ps = item as CFTypeRef
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue(),
                  let dict = desc as NSDictionary as? [String: Any] else { continue }
            if dict["Type"] as? String == "InternalBattery" { return dict }
        }
        return nil
    }

    // MARK: Storage

    static func storage() -> Storage? {
        let root = URL(fileURLWithPath: "/")
        guard let v = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                          .volumeAvailableCapacityForImportantUsageKey,
                                                          .volumeAvailableCapacityKey,
                                                          .volumeLocalizedNameKey]) else { return nil }
        var s = Storage()
        s.total = Int64(v.volumeTotalCapacity ?? 0)
        s.free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        s.volumeName = v.volumeLocalizedName
        let drive = internalDrive()
        s.model = drive.model
        s.isSSD = drive.isSSD
        return s
    }

    /// Model and medium of the first internal block storage device (best effort).
    private static func internalDrive() -> (model: String?, isSSD: Bool?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator) == KERN_SUCCESS else {
            return (nil, nil)
        }
        defer { IOObjectRelease(iterator) }
        var fallback: (model: String?, isSSD: Bool?)?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let device = property(entry, "Device Characteristics") as? [String: Any]
            let proto = property(entry, "Protocol Characteristics") as? [String: Any]
            IOObjectRelease(entry)
            let model = (device?["Product Name"] as? String)?.trimmingCharacters(in: .whitespaces)
            let medium = device?["Medium Type"] as? String
            let found: (model: String?, isSSD: Bool?) = (model, medium.map { $0 == "Solid State" })
            if proto?["Physical Interconnect Location"] as? String == "Internal" { return found }
            if fallback == nil && model != nil { fallback = found }
            entry = IOIteratorNext(iterator)
        }
        return fallback ?? (nil, nil)
    }

    // MARK: System

    static func system() -> SystemInfo {
        var s = SystemInfo()
        s.modelID = sysctlString("hw.model")
        s.modelName = productName()
        s.chip = sysctlString("machdep.cpu.brand_string")
        s.memoryBytes = ProcessInfo.processInfo.physicalMemory
        let v = ProcessInfo.processInfo.operatingSystemVersion
        s.osVersion = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
                                         : "\(v.majorVersion).\(v.minorVersion)"
        s.osBuild = sysctlString("kern.osversion")
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 {
            s.bootDate = Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
        } else {
            s.bootDate = Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
        }
        return s
    }

    /// Marketing name from the device tree ("MacBook Air (M2, 2022)"); Apple silicon only.
    private static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = property(entry, "product-name") as? Data else { return nil }
        let name = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
        return name.isEmpty ? nil : name
    }

    // MARK: Helpers

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let s = String(cString: buffer).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    /// All properties of the first service of `serviceClass`, nil when there is none.
    private static func registryProperties(serviceClass: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() else { return nil }
        return dict as NSDictionary as? [String: Any]
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
