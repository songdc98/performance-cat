// 性能监测猫猫 / Performance Cat — a tiny, native macOS performance dashboard.
//
// DISCLAIMER: This software is provided "AS IS", without warranty of any kind.
// It only READS local system metrics for display; it never modifies system state,
// never sends any data over the network, and requires no special entitlements
// beyond the OS-level access a user grants. The fan / power / temperature figures
// come from Apple's SMC and the bundled `macmon` helper and are best-effort — do
// not rely on them for safety-critical decisions. Use at your own risk.
//
// MIT-licensed. See LICENSE and README.md.

import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps

// MARK: - Localization
//
// The app ships as two separate builds — Chinese and English — chosen at compile
// time with `-D ENGLISH`. There is no in-app language switch (keeps the binary
// lean); pick the build you want on GitHub.

enum Lang { case zh, en }
#if ENGLISH
let appLang: Lang = .en
#else
let appLang: Lang = .zh
#endif

enum Thermal { case nominal, fair, serious, critical, unknown }
enum BatteryCondition { case ac, onBattery, charging, unknown }

struct Strings {
    var appName: String
    var starting: String
    var statusCalm, statusThermal, statusCPU, statusPower, statusRAM: String
    var vitalRAM: String
    var titleCPU, titlePower, titleRAM, titleFan, titleNet, titleStorage, titleBattery, titleAI, titleProc: String
    var subPower, subRAM, subNet, subStorage, subAI, subProc, subFanNone: String
    var subFan: (Int) -> String
    var cpuUser, cpuSystem, cpuIdle: String
    var powerSystem, thermalStatus: String
    var thermalText: (Thermal) -> String
    var fanLabel: (Int) -> String
    var fanStatus, fanNoteIdle, fanNoteLive, fanNoneNote: String
    var memPressure, memFree, memTop3, measuring: String
    var netTop3, netNone: String
    var storSystem, storData, storOther, storFree: String
    var storFreeOfTotal: (String) -> String
    var batteryStateText: (BatteryCondition) -> String
    var batPower, batAdapter, batCycles: String
    var aiDetail: (String, Int, String) -> String
    var aiNone, aiNoneCaption: String
    var uptime: (Int) -> String
    var nativeMode, waitingMacmon: String

    static let chinese = Strings(
        appName: "性能监测猫猫",
        starting: "性能监测猫猫正在启动…",
        statusCalm: "运行平稳", statusThermal: "散热压力升高", statusCPU: "CPU 高负载", statusPower: "高功率运行", statusRAM: "内存压力偏高",
        vitalRAM: "内存",
        titleCPU: "处理器", titlePower: "功率", titleRAM: "内存", titleFan: "散热", titleNet: "网络",
        titleStorage: "存储空间", titleBattery: "电池", titleAI: "AI 工具", titleProc: "活跃进程",
        subPower: "SoC · 系统功率 · 温度", subRAM: "统一内存 · 同活动监视器口径", subNet: "本机吞吐 · 进程流量",
        subStorage: "Macintosh HD · 分类占用", subAI: "Codex · Claude 进程", subProc: "CPU 占用排名", subFanNone: "风扇由系统托管",
        subFan: { "\($0) 风扇 · 系统自动调速" },
        cpuUser: "用户", cpuSystem: "系统", cpuIdle: "闲置",
        powerSystem: "系统功率", thermalStatus: "温度状态",
        thermalText: { switch $0 { case .nominal: return "正常"; case .fair: return "温和"; case .serious: return "偏热"; case .critical: return "临界"; case .unknown: return "未知" } },
        fanLabel: { "风扇 \($0)" },
        fanStatus: "状态", fanNoteIdle: "低温停转 · 由系统按温度自动调速", fanNoteLive: "实测转速 · 由系统按温度自动调速", fanNoneNote: "此机型未暴露风扇转速（或无风扇）",
        memPressure: "压力", memFree: "可用", memTop3: "内存占用前三（应用）", measuring: "统计中…",
        netTop3: "流量占用前三（进程，每秒）", netNone: "暂无明显进程流量",
        storSystem: "系统", storData: "数据", storOther: "其他", storFree: "可用",
        storFreeOfTotal: { "可用 / 共 \($0)" },
        batteryStateText: { switch $0 { case .ac: return "外接电源"; case .onBattery: return "电池供电"; case .charging: return "充电中"; case .unknown: return "未知" } },
        batPower: "充放功率", batAdapter: "适配器", batCycles: "循环次数",
        aiDetail: { "内存 \($0)  ·  \($1) 进程  ·  运行 \($2)" },
        aiNone: "未发现 Codex / Claude 进程", aiNoneCaption: "自动汇总名称含 codex / claude 的进程",
        uptime: { s in
            if s <= 0 { return "—" }
            let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
            if d > 0 { return "\(d)天\(h)时" }; if h > 0 { return "\(h)时\(m)分" }; if m > 0 { return "\(m)分" }; return "\(s)秒"
        },
        nativeMode: "原生模式", waitingMacmon: "等待 macmon"
    )

    static let english = Strings(
        appName: "Performance Cat",
        starting: "Performance Cat is starting…",
        statusCalm: "All clear", statusThermal: "Thermal pressure", statusCPU: "High CPU load", statusPower: "High power draw", statusRAM: "Memory pressure",
        vitalRAM: "RAM",
        titleCPU: "CPU", titlePower: "Power", titleRAM: "Memory", titleFan: "Cooling", titleNet: "Network",
        titleStorage: "Storage", titleBattery: "Battery", titleAI: "AI Tools", titleProc: "Top Processes",
        subPower: "SoC · system · temp", subRAM: "Unified memory · like Activity Monitor", subNet: "Throughput · per-process",
        subStorage: "Macintosh HD · by category", subAI: "Codex · Claude processes", subProc: "By CPU usage", subFanNone: "Fans managed by macOS",
        subFan: { "\($0) fans · auto-managed" },
        cpuUser: "User", cpuSystem: "System", cpuIdle: "Idle",
        powerSystem: "System power", thermalStatus: "Thermal",
        thermalText: { switch $0 { case .nominal: return "Nominal"; case .fair: return "Fair"; case .serious: return "Serious"; case .critical: return "Critical"; case .unknown: return "Unknown" } },
        fanLabel: { "Fan \($0)" },
        fanStatus: "Status", fanNoteIdle: "Idle (cool) · system auto-managed", fanNoteLive: "Live RPM · system auto-managed", fanNoneNote: "No fan sensor on this Mac (or fanless)",
        memPressure: "Pressure", memFree: "Free", memTop3: "Top 3 apps by memory", measuring: "Measuring…",
        netTop3: "Top 3 processes by traffic (per sec)", netNone: "No notable process traffic",
        storSystem: "System", storData: "Data", storOther: "Other", storFree: "Free",
        storFreeOfTotal: { "free / \($0) total" },
        batteryStateText: { switch $0 { case .ac: return "On AC power"; case .onBattery: return "On battery"; case .charging: return "Charging"; case .unknown: return "Unknown" } },
        batPower: "Power", batAdapter: "Adapter", batCycles: "Cycles",
        aiDetail: { "RAM \($0)  ·  \($1) procs  ·  up \($2)" },
        aiNone: "No Codex / Claude processes", aiNoneCaption: "Aggregates processes named codex / claude",
        uptime: { s in
            if s <= 0 { return "—" }
            let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
            if d > 0 { return "\(d)d \(h)h" }; if h > 0 { return "\(h)h \(m)m" }; if m > 0 { return "\(m)m" }; return "\(s)s"
        },
        nativeMode: "Native mode", waitingMacmon: "Waiting for macmon"
    )
}

let S: Strings = appLang == .en ? .english : .chinese

// Runs short-lived system tools with a hard timeout. Without this, one stuck
// ps/nettop/diskutil child can permanently freeze the sampler loop.
enum ProcessOutput {
    static func string(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        guard let data = data(executable, arguments, timeout: timeout) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func data(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        var output = Data()
        let lock = NSLock()
        let finished = DispatchSemaphore(value: 0)

        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            output.append(data)
            lock.unlock()
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in append(handle.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForWriting.closeFile()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            stdout.fileHandleForReading.closeFile()
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForReading.closeFile()
            stderr.fileHandleForWriting.closeFile()
            return nil
        }

        let timeoutMs = max(1, Int(timeout * 1000))
        let timedOut = finished.wait(timeout: .now() + .milliseconds(timeoutMs)) == .timedOut
        var exited = !timedOut
        if timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + .milliseconds(500)) == .success {
                exited = true
            } else {
                kill(process.processIdentifier, SIGKILL)
                exited = finished.wait(timeout: .now() + .milliseconds(500)) == .success
            }
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        guard exited else {
            stdout.fileHandleForReading.closeFile()
            stderr.fileHandleForReading.closeFile()
            return nil
        }
        append(stdout.fileHandleForReading.readDataToEndOfFile())
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        stdout.fileHandleForReading.closeFile()
        stderr.fileHandleForReading.closeFile()

        guard !timedOut, process.terminationStatus == 0 else { return nil }
        lock.lock()
        let result = output
        lock.unlock()
        return result
    }
}

// MARK: - Models

struct CPUStats {
    var user: Double
    var system: Double
    var idle: Double
    var active: Double { max(0, min(1, user + system)) }
}

struct MemoryStats {
    var used: UInt64
    var total: UInt64
    var swapUsed: UInt64?
    var ratio: Double { total == 0 ? 0 : Double(used) / Double(total) }
    var free: UInt64 { total > used ? total - used : 0 }
}

struct AppUsage {
    var name: String
    var rss: UInt64
    var cpu: Double
}

struct NetworkStats {
    var downPerSecond: Double
    var upPerSecond: Double
}

struct NetworkApp {
    var name: String
    var downPerSecond: Double
    var upPerSecond: Double
}

struct BatteryStats {
    var percent: Double?
    var state: BatteryCondition
    var watts: Double?
    var adapterWatts: Double?
    var cycles: Int?
}

struct ProcessStats {
    var name: String
    var cpu: Double
}

struct AIToolUsage {
    var cpu: Double = 0
    var memory: UInt64 = 0
    var processes: Int = 0
    var uptimeSeconds: Int = 0
    var hasAny: Bool { cpu > 0 || memory > 0 || processes > 0 }
}

struct AIUsage {
    var codex = AIToolUsage()
    var claude = AIToolUsage()
    var hasAny: Bool { codex.hasAny || claude.hasAny }
}

struct FanInfo {
    var rpm: Double
    var minRPM: Double
    var maxRPM: Double
}

struct SensorStats {
    var source: String
    var cpuTempC: Double?
    var gpuTempC: Double?
    var cpuPowerW: Double?
    var gpuPowerW: Double?
    var anePowerW: Double?
    var ramPowerW: Double?
    var systemPowerW: Double?
    var allPowerW: Double?
    var ramUsedBytes: UInt64?
    var swapBytes: UInt64?
}

struct StorageBreakdown {
    var total: UInt64
    var free: UInt64
    var systemUsed: UInt64
    var dataUsed: UInt64
    var otherUsed: UInt64
    var used: UInt64 { total > free ? total - free : 0 }
}

struct MetricsSnapshot {
    var timestamp: Date
    var chipName: String
    var cpu: CPUStats
    var memory: MemoryStats
    var network: NetworkStats
    var battery: BatteryStats
    var thermalState: Thermal
    var sensors: SensorStats
    var fans: [FanInfo]
    var storage: StorageBreakdown?
    var topProcesses: [ProcessStats]
    var topMemoryApps: [AppUsage]
    var networkApps: [NetworkApp]
    var aiUsage: AIUsage
}

// MARK: - SMC fan reader (IOKit AppleSMC, read-only, no privileges)

final class SMCFanReader {
    private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    private struct SMCVersion { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct SMCPLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
    // dataAttributes is padded to 12 bytes so the whole param struct matches the kernel's 80-byte layout.
    private struct SMCKeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0; var pad0: UInt8 = 0; var pad1: UInt8 = 0; var pad2: UInt8 = 0 }
    private struct SMCParam {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimit = SMCPLimit()
        var keyInfo = SMCKeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private let kSMCIndex: UInt32 = 2
    private let cmdReadBytes: UInt8 = 5
    private let cmdReadKeyInfo: UInt8 = 9
    private var conn: io_connect_t = 0
    private(set) var available = false

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess {
            available = true
        }
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    func readFans() -> [FanInfo] {
        guard available else { return [] }
        guard let count = readUInt8("FNum"), count > 0, count < 12 else { return [] }
        var fans: [FanInfo] = []
        for i in 0..<Int(count) {
            let rpm = readFloat("F\(i)Ac") ?? 0
            let minR = readFloat("F\(i)Mn") ?? 0
            let maxR = readFloat("F\(i)Mx") ?? 0
            fans.append(FanInfo(rpm: max(0, rpm), minRPM: max(0, minR), maxRPM: max(0, maxR)))
        }
        return fans
    }

    private func fourCC(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for b in s.utf8 { r = (r << 8) + UInt32(b) }
        return r
    }

    private func call(_ input: inout SMCParam) -> SMCParam? {
        var output = SMCParam()
        let inSize = MemoryLayout<SMCParam>.stride
        var outSize = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(conn, kSMCIndex, &input, inSize, &output, &outSize)
        return r == kIOReturnSuccess ? output : nil
    }

    private func readBytes(_ key: String) -> (type: UInt32, bytes: SMCBytes)? {
        var info = SMCParam()
        info.key = fourCC(key)
        info.data8 = cmdReadKeyInfo
        guard let infoOut = call(&info) else { return nil }
        var read = SMCParam()
        read.key = fourCC(key)
        read.keyInfo = infoOut.keyInfo
        read.data8 = cmdReadBytes
        guard let out = call(&read) else { return nil }
        return (infoOut.keyInfo.dataType, out.bytes)
    }

    private func readFloat(_ key: String) -> Double? {
        guard let (type, b) = readBytes(key) else { return nil }
        // "flt " little-endian Float32 (Apple Silicon); "fpe2" big-endian fixed point.
        if type == fourCC("flt ") {
            let raw = UInt32(b.0) | (UInt32(b.1) << 8) | (UInt32(b.2) << 16) | (UInt32(b.3) << 24)
            return Double(Float(bitPattern: raw))
        }
        if type == fourCC("fpe2") {
            return Double((UInt16(b.0) << 8) | UInt16(b.1)) / 4.0
        }
        return nil
    }

    private func readUInt8(_ key: String) -> UInt8? {
        guard let (_, b) = readBytes(key) else { return nil }
        return b.0
    }
}

// MARK: - macmon sensor bridge (bundled helper; power + temperature)

private struct MacmonPayload: Decodable {
    struct Temp: Decodable { var cpu_temp_avg: Double?; var gpu_temp_avg: Double? }
    struct Memory: Decodable { var ram_usage: UInt64?; var ram_total: UInt64?; var swap_usage: UInt64? }
    var temp: Temp?
    var memory: Memory?
    var cpu_power: Double?
    var gpu_power: Double?
    var ane_power: Double?
    var ram_power: Double?
    var sys_power: Double?
    var all_power: Double?
}

final class MacmonBridge {
    private let queue = DispatchQueue(label: "local.song.performance-cat.macmon")
    private var process: Process?
    private var buffer = Data()
    private var latestPayload: MacmonPayload?
    private(set) var binaryPath: String?

    init() {
        binaryPath = Self.findBinary()
        start()
    }

    deinit { process?.terminate() }

    func latest() -> SensorStats {
        let payload = queue.sync { latestPayload }
        guard let payload else {
            return SensorStats(source: binaryPath == nil ? S.nativeMode : S.waitingMacmon,
                               cpuTempC: nil, gpuTempC: nil, cpuPowerW: nil, gpuPowerW: nil,
                               anePowerW: nil, ramPowerW: nil, systemPowerW: nil, allPowerW: nil,
                               ramUsedBytes: nil, swapBytes: nil)
        }
        return SensorStats(source: "macmon",
                           cpuTempC: payload.temp?.cpu_temp_avg,
                           gpuTempC: payload.temp?.gpu_temp_avg,
                           cpuPowerW: payload.cpu_power,
                           gpuPowerW: payload.gpu_power,
                           anePowerW: payload.ane_power,
                           ramPowerW: payload.ram_power,
                           systemPowerW: payload.sys_power,
                           allPowerW: payload.all_power,
                           ramUsedBytes: payload.memory?.ram_usage,
                           swapBytes: payload.memory?.swap_usage)
    }

    private func start() {
        guard let path = binaryPath else { return }
        let process = Process()
        let out = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["pipe", "-i", "2000"]
        process.standardOutput = out
        process.standardError = Pipe()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        do {
            try process.run()
            self.process = process
        } catch {
            binaryPath = nil
        }
    }

    private func consume(_ data: Data) {
        queue.async {
            self.buffer.append(data)
            let newline = Data([0x0A])
            while let range = self.buffer.range(of: newline) {
                let line = self.buffer.subdata(in: self.buffer.startIndex..<range.lowerBound)
                self.buffer.removeSubrange(self.buffer.startIndex...range.lowerBound)
                guard !line.isEmpty else { continue }
                if let payload = try? JSONDecoder().decode(MacmonPayload.self, from: line) {
                    self.latestPayload = payload
                }
            }
        }
    }

    private static func findBinary() -> String? {
        var candidates: [String] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("macmon").path {
            candidates.append(bundled)
        }
        candidates += ["/opt/homebrew/bin/macmon", "/usr/local/bin/macmon", "/run/current-system/sw/bin/macmon"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/macmon" }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Per-process network (nettop, sampled on a background thread)

final class NetTopReader {
    private let queue = DispatchQueue(label: "local.song.performance-cat.nettop")
    private var cached: [NetworkApp] = []
    private let lock = NSLock()
    private var running = true

    init() { loop() }
    deinit { running = false }

    func latest() -> [NetworkApp] {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    private func loop() {
        queue.async { [weak self] in
            while self?.running == true {
                if let apps = self?.sampleOnce() {
                    self?.lock.lock(); self?.cached = apps; self?.lock.unlock()
                }
                Thread.sleep(forTimeInterval: 3.0)
            }
        }
    }

    // Two cumulative frames 1s apart; per-process delta = bytes/second.
    private func sampleOnce() -> [NetworkApp]? {
        guard let text = ProcessOutput.string(
            "/usr/bin/nettop",
            ["-P", "-x", "-L", "2", "-s", "1", "-J", "bytes_in,bytes_out"],
            timeout: 5.0
        ) else { return nil }
        return Self.parse(text)
    }

    private static func parse(_ text: String) -> [NetworkApp] {
        var frames: [[String: (UInt64, UInt64)]] = []
        var current: [String: (UInt64, UInt64)] = [:]
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if cols.count < 3 { continue }
            if cols[1] == "bytes_in" { // frame header
                if !current.isEmpty { frames.append(current); current = [:] }
                continue
            }
            guard let inB = UInt64(cols[1]), let outB = UInt64(cols[2]) else { continue }
            let name = cleanName(cols[0])
            let existing = current[name] ?? (0, 0)
            current[name] = (existing.0 + inB, existing.1 + outB)
        }
        if !current.isEmpty { frames.append(current) }
        guard frames.count >= 2 else { return [] }
        let first = frames[frames.count - 2]
        let second = frames[frames.count - 1]
        var apps: [NetworkApp] = []
        for (name, late) in second {
            let early = first[name] ?? (0, 0)
            let down = late.0 >= early.0 ? Double(late.0 - early.0) : 0
            let up = late.1 >= early.1 ? Double(late.1 - early.1) : 0
            if down + up > 0 { apps.append(NetworkApp(name: name, downPerSecond: down, upPerSecond: up)) }
        }
        return apps.sorted { ($0.downPerSecond + $0.upPerSecond) > ($1.downPerSecond + $1.upPerSecond) }
    }

    private static func cleanName(_ raw: String) -> String {
        // nettop labels are "name.pid"; drop the trailing pid.
        if let dot = raw.lastIndex(of: "."), raw[raw.index(after: dot)...].allSatisfy(\.isNumber) {
            return String(raw[..<dot])
        }
        return raw
    }
}

// MARK: - Storage breakdown (diskutil apfs list, sampled occasionally)

final class StorageReader {
    private let queue = DispatchQueue(label: "local.song.performance-cat.storage")
    private var cached: StorageBreakdown?
    private let lock = NSLock()
    private var running = true

    init() { loop() }
    deinit { running = false }

    func latest() -> StorageBreakdown? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    private func loop() {
        queue.async { [weak self] in
            while self?.running == true {
                if let s = self?.sampleOnce() {
                    self?.lock.lock(); self?.cached = s; self?.lock.unlock()
                }
                // Disk usage changes slowly; sampling every 5 min keeps the diskutil cost negligible.
                Thread.sleep(forTimeInterval: 300.0)
            }
        }
    }

    private func sampleOnce() -> StorageBreakdown? {
        guard let data = ProcessOutput.data("/usr/sbin/diskutil", ["apfs", "list", "-plist"], timeout: 8.0) else { return nil }
        return Self.parse(data)
    }

    private static func parse(_ data: Data) -> StorageBreakdown? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let containers = plist["Containers"] as? [[String: Any]] else { return nil }
        // Pick the boot container — the one that owns a "Data" role volume.
        for container in containers {
            guard let volumes = container["Volumes"] as? [[String: Any]] else { continue }
            let hasData = volumes.contains { ($0["Roles"] as? [String])?.contains("Data") == true }
            guard hasData else { continue }
            let total = (container["CapacityCeiling"] as? NSNumber)?.uint64Value ?? 0
            let free = (container["CapacityFree"] as? NSNumber)?.uint64Value ?? 0
            var system: UInt64 = 0, dataU: UInt64 = 0, other: UInt64 = 0
            for v in volumes {
                let inUse = (v["CapacityInUse"] as? NSNumber)?.uint64Value ?? 0
                let roles = (v["Roles"] as? [String]) ?? []
                if roles.contains("System") { system += inUse }
                else if roles.contains("Data") { dataU += inUse }
                else { other += inUse }
            }
            return StorageBreakdown(total: total, free: free, systemUsed: system, dataUsed: dataU, otherUsed: other)
        }
        return nil
    }
}

// MARK: - Metrics provider

final class MetricsProvider {
    private var previousCPU: [UInt64]?
    private var previousNetwork: (rx: UInt64, tx: UInt64, time: Date)?
    private var cachedProcesses: [ProcessStats] = []
    private var cachedMemApps: [AppUsage] = []
    private var cachedAIUsage = AIUsage()
    private var processReadTime = Date.distantPast
    private let chipName: String
    private let macmon = MacmonBridge()
    private let smc = SMCFanReader()
    private let nettop = NetTopReader()
    private let storage = StorageReader()

    init() { chipName = Self.readChipName() }

    func snapshot() -> MetricsSnapshot {
        let now = Date()
        if now.timeIntervalSince(processReadTime) > 4 {
            if let data = Self.readProcesses() {
                cachedProcesses = data.top
                cachedMemApps = data.memApps
                cachedAIUsage = data.ai
            }
            processReadTime = now
        }
        return MetricsSnapshot(
            timestamp: now,
            chipName: chipName,
            cpu: readCPU(),
            memory: readMemory(),
            network: readNetwork(),
            battery: Self.readBattery(),
            thermalState: Self.thermalStateText(),
            sensors: macmon.latest(),
            fans: smc.readFans(),
            storage: storage.latest(),
            topProcesses: cachedProcesses,
            topMemoryApps: cachedMemApps,
            networkApps: nettop.latest(),
            aiUsage: cachedAIUsage
        )
    }

    private static func readChipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private func readCPU() -> CPUStats {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount = mach_msg_type_number_t(0)
        var processorCount = natural_t(0)
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &cpuInfo, &cpuInfoCount)
        guard result == KERN_SUCCESS, let cpuInfo else { return CPUStats(user: 0, system: 0, idle: 1) }
        defer {
            let byteCount = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), byteCount)
        }
        let stateCount = Int(CPU_STATE_MAX)
        let sampleCount = Int(processorCount) * stateCount
        var current = [UInt64](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount { current[index] = UInt64(max(0, cpuInfo[index])) }
        guard let previousCPU, previousCPU.count == current.count else {
            self.previousCPU = current
            return CPUStats(user: 0, system: 0, idle: 1)
        }
        var userTicks: UInt64 = 0, systemTicks: UInt64 = 0, idleTicks: UInt64 = 0, totalTicks: UInt64 = 0
        for cpuIndex in 0..<Int(processorCount) {
            let base = cpuIndex * stateCount
            let user = delta(current[base + Int(CPU_STATE_USER)], previousCPU[base + Int(CPU_STATE_USER)])
            let nice = delta(current[base + Int(CPU_STATE_NICE)], previousCPU[base + Int(CPU_STATE_NICE)])
            let system = delta(current[base + Int(CPU_STATE_SYSTEM)], previousCPU[base + Int(CPU_STATE_SYSTEM)])
            let idle = delta(current[base + Int(CPU_STATE_IDLE)], previousCPU[base + Int(CPU_STATE_IDLE)])
            userTicks += user + nice; systemTicks += system; idleTicks += idle
            totalTicks += user + nice + system + idle
        }
        self.previousCPU = current
        guard totalTicks > 0 else { return CPUStats(user: 0, system: 0, idle: 1) }
        return CPUStats(user: Double(userTicks) / Double(totalTicks),
                        system: Double(systemTicks) / Double(totalTicks),
                        idle: Double(idleTicks) / Double(totalTicks))
    }

    private func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 { current >= previous ? current - previous : 0 }

    private func readMemory() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        let sensors = macmon.latest()
        var used: UInt64 = 0
        if let macmonUsed = sensors.ramUsedBytes, macmonUsed > 0 {
            used = min(total, macmonUsed)
        } else if result == KERN_SUCCESS {
            var pageSize = vm_size_t(0)
            host_page_size(mach_host_self(), &pageSize)
            let page = UInt64(pageSize)
            let computed = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
            used = min(total, computed)
        }
        let swap = sensors.swapBytes ?? Self.readSwapUsage()
        return MemoryStats(used: used, total: total, swapUsed: swap)
    }

    private static func readSwapUsage() -> UInt64? {
        guard let text = ProcessOutput.string("/usr/sbin/sysctl", ["-n", "vm.swapusage"], timeout: 1.5) else { return nil }
        let pattern = #"used = ([0-9.]+)([MG])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]) else { return nil }
        let multiplier = text[unitRange] == "G" ? 1024.0 * 1024.0 * 1024.0 : 1024.0 * 1024.0
        return UInt64(value * multiplier)
    }

    private func readNetwork() -> NetworkStats {
        let totals = Self.readNetworkTotals()
        let now = Date()
        defer { previousNetwork = (totals.rx, totals.tx, now) }
        guard let previousNetwork else { return NetworkStats(downPerSecond: 0, upPerSecond: 0) }
        let elapsed = max(0.5, now.timeIntervalSince(previousNetwork.time))
        let rxDelta = totals.rx >= previousNetwork.rx ? totals.rx - previousNetwork.rx : 0
        let txDelta = totals.tx >= previousNetwork.tx ? totals.tx - previousNetwork.tx : 0
        return NetworkStats(downPerSecond: Double(rxDelta) / elapsed, upPerSecond: Double(txDelta) / elapsed)
    }

    private static func readNetworkTotals() -> (rx: UInt64, tx: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, let data = interface.ifa_data {
                let s = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(s.ifi_ibytes); tx += UInt64(s.ifi_obytes)
            }
            ptr = interface.ifa_next
        }
        return (rx, tx)
    }

    private static func readBattery() -> BatteryStats {
        var percent: Double?
        var state: BatteryCondition = .unknown
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
                if let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
                   let max = description[kIOPSMaxCapacityKey] as? NSNumber, max.doubleValue > 0 {
                    percent = current.doubleValue / max.doubleValue
                }
                if let powerState = description[kIOPSPowerSourceStateKey] as? String {
                    state = powerState == kIOPSACPowerValue ? .ac : .onBattery
                }
                if let charging = description[kIOPSIsChargingKey] as? Bool, charging { state = .charging }
            }
        }
        let smc = readBatteryRegistry()
        return BatteryStats(percent: percent, state: state, watts: smc.watts, adapterWatts: smc.adapterWatts, cycles: smc.cycles)
    }

    private static func readBatteryRegistry() -> (watts: Double?, adapterWatts: Double?, cycles: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil, nil) }
        defer { IOObjectRelease(service) }
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanagedProperties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any] else { return (nil, nil, nil) }
        func double(_ key: String) -> Double? { (properties[key] as? NSNumber)?.doubleValue }
        let voltage = double("Voltage")
        let amperage = double("InstantAmperage") ?? double("Amperage")
        let watts: Double? = (voltage != nil && amperage != nil) ? abs(voltage! * amperage!) / 1_000_000.0 : nil
        var adapterWatts: Double?
        if let adapter = properties["AdapterDetails"] as? [String: Any], let value = adapter["Watts"] as? NSNumber {
            adapterWatts = value.doubleValue
        }
        let cycles = (properties["CycleCount"] as? NSNumber)?.intValue
        return (watts, adapterWatts, cycles)
    }

    private static func thermalStateText() -> Thermal {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }

    // Reads ps once and derives: top CPU processes, the top memory-using apps, and AI-tool usage.
    private static func readProcesses() -> (top: [ProcessStats], memApps: [AppUsage], ai: AIUsage)? {
        guard let output = ProcessOutput.string("/bin/ps", ["-axo", "pcpu=,rss=,etime=,comm="], timeout: 2.0) else { return nil }

        var processes: [ProcessStats] = []
        var ai = AIUsage()
        // Aggregate by application bundle (so an app's helpers sum together).
        var apps: [String: (rss: UInt64, cpu: Double, isUserApp: Bool)] = [:]

        for line in output.split(separator: "\n") {
            // Fields: pcpu rss etime path. etime ("[[dd-]hh:]mm:ss") has no spaces; the path may.
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let cpu = Double(parts[0]), let rssKB = UInt64(parts[1]) else { continue }
            let uptime = parseETime(String(parts[2]))
            let path = String(parts[3])
            let memory = rssKB * 1024
            let procName = URL(fileURLWithPath: path).lastPathComponent
            processes.append(ProcessStats(name: procName, cpu: cpu))

            let lower = path.lowercased()
            if lower.contains("codex") { accumulate(&ai.codex, cpu: cpu, memory: memory, uptime: uptime) }
            if lower.contains("claude") { accumulate(&ai.claude, cpu: cpu, memory: memory, uptime: uptime) }

            let app = appName(for: path)
            let isUserApp = path.contains("/Applications/")
            var entry = apps[app] ?? (0, 0, false)
            entry.rss += memory; entry.cpu += cpu; entry.isUserApp = entry.isUserApp || isUserApp
            apps[app] = entry
        }

        guard !processes.isEmpty else { return nil }
        let top = Array(processes.sorted { $0.cpu > $1.cpu }.prefix(6))
        // Top three memory-using applications.
        let memApps = apps.filter { $0.value.isUserApp }
            .sorted { $0.value.rss > $1.value.rss }.prefix(3)
            .map { AppUsage(name: $0.key, rss: $0.value.rss, cpu: $0.value.cpu) }

        return (top, memApps, ai)
    }

    private static func accumulate(_ tool: inout AIToolUsage, cpu: Double, memory: UInt64, uptime: Int) {
        tool.cpu += cpu
        tool.memory += memory
        tool.processes += 1
        tool.uptimeSeconds = max(tool.uptimeSeconds, uptime)  // oldest helper ≈ when the app launched
    }

    // Parse ps `etime` ("[[dd-]hh:]mm:ss") into seconds.
    private static func parseETime(_ s: String) -> Int {
        var days = 0
        var timePart = Substring(s)
        if let dash = s.firstIndex(of: "-") {
            days = Int(s[..<dash]) ?? 0
            timePart = s[s.index(after: dash)...]
        }
        let comps = timePart.split(separator: ":").map { Int($0) ?? 0 }
        var h = 0, m = 0, sec = 0
        switch comps.count {
        case 3: h = comps[0]; m = comps[1]; sec = comps[2]
        case 2: m = comps[0]; sec = comps[1]
        case 1: sec = comps[0]
        default: break
        }
        return days * 86400 + h * 3600 + m * 60 + sec
    }

    private static func appName(for path: String) -> String {
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            return URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

// MARK: - Dashboard view

final class DashboardView: NSView {
    private var snapshot: MetricsSnapshot?
    private var cpuHistory: [Double] = []
    private var powerHistory: [Double] = []
    private var netHistory: [Double] = []
    private let maxHistory = 80
    private lazy var appIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSApp.applicationIconImage
    }()

    // We render the whole dashboard into an offscreen bitmap and hand it to the view's
    // layer as `contents`. Drawing this complex content directly into the window's
    // backing on Apple Silicon makes the GPU allocate a large transient surface every
    // frame (footprint spikes to ~270 MB); rendering offscreen keeps it flat.
    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        // .resize lets the current bitmap stretch smoothly during a live drag,
        // then each setFrameSize re-renders it crisp — cards float fluidly.
        layer.contentsGravity = .resize
        layer.isOpaque = true
        return layer
    }

    func update(_ snapshot: MetricsSnapshot) {
        self.snapshot = snapshot
        append(&cpuHistory, snapshot.cpu.active)
        let systemPower = snapshot.sensors.systemPowerW ?? snapshot.sensors.allPowerW ?? snapshot.battery.watts ?? 0
        append(&powerHistory, min(1, systemPower / 120.0))
        append(&netHistory, min(1, (snapshot.network.downPerSecond + snapshot.network.upPerSecond) / (25.0 * 1024.0 * 1024.0)))
        renderToLayer()
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(max(0, min(1, value)))
        if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
    }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        renderToLayer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderToLayer()
    }

    private func renderToLayer() {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let pw = Int(size.width * scale), ph = Int(size.height * scale)
        guard pw > 0, ph > 0 else { return }
        autoreleasepool {
            // Draw into one CPU bitmap context; CGBitmapContext makeImage() is copy-on-write,
            // so the layer's image shares the buffer (deterministic, low, flat memory).
            guard let cg = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            cg.scaleBy(x: scale, y: scale)          // device px → points
            cg.translateBy(x: 0, y: size.height)    // flip to top-left origin (isFlipped layout)
            cg.scaleBy(x: 1, y: -1)
            cg.setShouldAntialias(true)
            let ns = NSGraphicsContext(cgContext: cg, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            renderContent()
            NSGraphicsContext.restoreGraphicsState()
            guard let cgImage = cg.makeImage() else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = scale
            layer?.contents = cgImage
            CATransaction.commit()
        }
    }

    private func renderContent() {
        drawBackground()
        guard let snapshot else {
            drawText(S.starting, in: bounds.insetBy(dx: 32, dy: 32), size: 22, weight: .semibold, color: textPrimary)
            return
        }

        // Slim margins + low floors so the 3×3 grid reflows freely down to a
        // portrait-screen width (cards shrink with the window instead of clipping).
        let margin: CGFloat = 14
        let gap: CGFloat = 12
        let headerH: CGFloat = 36
        let contentTop = margin + headerH + 14
        let colW = max(210, (bounds.width - margin * 2 - gap * 2) / 3)
        let availableH = max(420, bounds.height - contentTop - margin)
        let usableH = availableH - gap * 2
        let row1H = usableH * 0.31
        let row2H = usableH * 0.37
        let row3H = usableH * 0.32

        drawHeader(snapshot, rect: NSRect(x: margin, y: margin, width: bounds.width - margin * 2, height: headerH))

        let x0 = margin, x1 = margin + colW + gap, x2 = margin + (colW + gap) * 2
        let y0 = contentTop, y1 = y0 + row1H + gap, y2 = y1 + row2H + gap

        drawCPU(snapshot, rect: NSRect(x: x0, y: y0, width: colW, height: row1H))
        drawPower(snapshot, rect: NSRect(x: x1, y: y0, width: colW, height: row1H))
        drawFans(snapshot, rect: NSRect(x: x2, y: y0, width: colW, height: row1H))
        drawMemory(snapshot, rect: NSRect(x: x0, y: y1, width: colW, height: row2H))
        drawNetwork(snapshot, rect: NSRect(x: x1, y: y1, width: colW, height: row2H))
        drawAI(snapshot, rect: NSRect(x: x2, y: y1, width: colW, height: row2H))
        drawBattery(snapshot, rect: NSRect(x: x0, y: y2, width: colW, height: row3H))
        drawStorage(snapshot, rect: NSRect(x: x1, y: y2, width: colW, height: row3H))
        drawProcesses(snapshot, rect: NSRect(x: x2, y: y2, width: colW, height: row3H))
    }

    private func drawBackground() {
        // Solid fill — per-frame gradient rasterization allocates a large transient GPU
        // surface on Apple Silicon, so we avoid NSGradient/CGGradient in the draw loop.
        bgTop.setFill()
        bounds.fill()
    }

    // MARK: Header status strip

    private struct Severity { var word: String; var color: NSColor }

    private func statusSeverity(_ s: MetricsSnapshot) -> Severity {
        let ramRatio = s.memory.ratio
        let power = s.sensors.systemPowerW ?? s.sensors.allPowerW ?? 0
        if s.thermalState == .critical { return Severity(word: S.statusThermal, color: crit) }
        if s.thermalState == .serious { return Severity(word: S.statusThermal, color: warn) }
        if s.cpu.active > 0.75 { return Severity(word: S.statusCPU, color: warn) }
        if power > 70 { return Severity(word: S.statusPower, color: warn) }
        if ramRatio > 0.80 { return Severity(word: S.statusRAM, color: warn) }
        return Severity(word: S.statusCalm, color: ok)
    }

    private func drawHeader(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        let sev = statusSeverity(s)
        // App icon (brand mark) at the far left of the header.
        let iconSize: CGFloat = 22
        let iconRect = NSRect(x: rect.minX + 14, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize)
        appIcon?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        let statusX = iconRect.maxX + 11
        let dotR: CGFloat = 7
        let dot = NSBezierPath(ovalIn: NSRect(x: statusX, y: rect.midY - dotR / 2, width: dotR, height: dotR))
        sev.color.setFill(); dot.fill()
        let wordFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let wordW = textWidth(sev.word, font: wordFont)
        drawText(sev.word, in: NSRect(x: statusX + dotR + 8, y: rect.minY + 9, width: wordW + 8, height: 18), font: wordFont, color: sev.color)

        // Right-aligned vitals: SoC W · CPU ° · GPU ° · 内存 %
        var segs: [(String, String)] = []
        if let p = s.sensors.allPowerW ?? s.sensors.systemPowerW ?? s.battery.watts { segs.append(("SoC", "\(fmt(p, 1)) W")) }
        if let t = s.sensors.cpuTempC { segs.append(("CPU", "\(fmt(t, 1))\u{2009}°C")) }
        if let t = s.sensors.gpuTempC { segs.append(("GPU", "\(fmt(t, 1))\u{2009}°C")) }
        if s.memory.total > 0 { segs.append((S.vitalRAM, "\(Int(round(s.memory.ratio * 100))) %")) }

        let labelFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let valueFont = tabFont(12.5, .medium)
        let segGap: CGFloat = 22
        var widths: [CGFloat] = []
        for seg in segs { widths.append(textWidth(seg.0, font: labelFont) + 5 + textWidth(seg.1, font: valueFont)) }
        let totalW = widths.reduce(0, +) + segGap * CGFloat(max(0, segs.count - 1))
        var x = rect.maxX - 18 - totalW
        for (i, seg) in segs.enumerated() {
            let lw = textWidth(seg.0, font: labelFont)
            drawText(seg.0, in: NSRect(x: x, y: rect.minY + 11, width: lw + 4, height: 16), font: labelFont, color: textTertiary)
            drawText(seg.1, in: NSRect(x: x + lw + 5, y: rect.minY + 10, width: widths[i], height: 18), font: valueFont, color: textSecondary)
            x += widths[i] + segGap
        }
    }

    // MARK: Cards

    private func drawCPU(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        drawSectionTitle(S.titleCPU, subtitle: s.chipName, rect: rect, glyph: .cpu)
        let pct = Int(round(s.cpu.active * 100))
        drawNumberUnit("\(pct)", unit: "%", numberFont: heroFont(30), unitFont: tabFont(14, .medium),
                       numberColor: cpuHue, unitColor: textTertiary, at: NSPoint(x: rect.minX + 18, y: rect.minY + 48))
        if let temp = s.sensors.cpuTempC {
            drawText("\(fmt(temp, 1))\u{2009}°C", in: NSRect(x: rect.maxX - 110, y: rect.minY + 58, width: 92, height: 18),
                     font: tabFont(13, .medium), color: textSecondary, align: .right)
        }
        drawSparkline(cpuHistory, rect: NSRect(x: rect.minX + 18, y: rect.minY + 88, width: rect.width - 36, height: 44), hue: cpuHue)
        drawStackBar(rect: NSRect(x: rect.minX + 18, y: rect.minY + 138, width: rect.width - 36, height: 8),
                     segments: [(s.cpu.user, chUser), (s.cpu.system, chSystem), (s.cpu.idle, trackIdle)])
        let ly = rect.minY + 150
        drawLegend(S.cpuUser, value: "\(fmt(s.cpu.user * 100, 1)) %", color: chUser, x: rect.minX + 18, y: ly, width: rect.width - 36)
        drawLegend(S.cpuSystem, value: "\(fmt(s.cpu.system * 100, 1)) %", color: chSystem, x: rect.minX + 18, y: ly + 18, width: rect.width - 36)
        drawLegend(S.cpuIdle, value: "\(fmt(s.cpu.idle * 100, 1)) %", color: trackIdle, x: rect.minX + 18, y: ly + 36, width: rect.width - 36)
    }

    private func drawPower(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        drawSectionTitle(S.titlePower, subtitle: S.subPower, rect: rect, glyph: .power)
        let systemPower = s.sensors.systemPowerW ?? s.sensors.allPowerW ?? (s.battery.watts.flatMap { $0 > 0.2 ? $0 : nil })
        drawNumberUnit(systemPower.map { fmt($0, 1) } ?? "—", unit: "W", numberFont: heroFont(30), unitFont: tabFont(14, .medium),
                       numberColor: pwrHue, unitColor: textTertiary, at: NSPoint(x: rect.minX + 18, y: rect.minY + 46))
        let socText = s.sensors.allPowerW.map { "\(S.powerSystem) · SoC \(fmt($0, 1)) W" } ?? S.powerSystem
        drawText(socText, in: NSRect(x: rect.minX + 18, y: rect.minY + 82, width: rect.width - 36, height: 16),
                 size: 11, weight: .regular, color: textTertiary)
        drawSparkline(powerHistory, rect: NSRect(x: rect.minX + 18, y: rect.minY + 102, width: rect.width - 36, height: 30), hue: pwrHue)
        let colGap: CGFloat = 14
        let halfW = (rect.width - 36 - colGap) / 2
        let leftX = rect.minX + 18, rightX = rect.minX + 18 + halfW + colGap
        let gy = rect.minY + 146
        drawMetricRow("CPU", value: powerStr(s.sensors.cpuPowerW), dot: chUser, rect: NSRect(x: leftX, y: gy, width: halfW, height: 16))
        drawMetricRow("GPU", value: powerStr(s.sensors.gpuPowerW), dot: chGPU, rect: NSRect(x: rightX, y: gy, width: halfW, height: 16))
        drawMetricRow("ANE", value: powerStr(s.sensors.anePowerW), dot: chANE, rect: NSRect(x: leftX, y: gy + 22, width: halfW, height: 16))
        drawMetricRow("DRAM", value: powerStr(s.sensors.ramPowerW), dot: chDRAM, rect: NSRect(x: rightX, y: gy + 22, width: halfW, height: 16))
        drawMetricRow(S.thermalStatus, value: S.thermalText(s.thermalState), dot: thermalColor(s.thermalState),
                      rect: NSRect(x: leftX, y: rect.minY + 192, width: rect.width - 36, height: 16), valueColor: thermalColor(s.thermalState))
    }

    private func drawFans(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        let fans = s.fans
        drawSectionTitle(S.titleFan, subtitle: fans.isEmpty ? S.subFanNone : S.subFan(fans.count), rect: rect, glyph: .fan)

        if !fans.isEmpty {
            let heroRPM = fans.map { $0.rpm }.max() ?? 0
            let allOff = heroRPM <= 0
            drawNumberUnit("\(Int(heroRPM))", unit: "RPM", numberFont: heroFont(30), unitFont: tabFont(14, .medium),
                           numberColor: allOff ? textTertiary : thermHue, unitColor: textTertiary, at: NSPoint(x: rect.minX + 18, y: rect.minY + 46))
            var y = rect.minY + 88
            for (i, fan) in fans.prefix(2).enumerated() {
                let pct = fan.maxRPM > 0 ? fan.rpm / fan.maxRPM : 0
                drawMetricRow(S.fanLabel(i + 1), value: "\(Int(fan.rpm)) RPM", dot: thermHue,
                              rect: NSRect(x: rect.minX + 18, y: y, width: rect.width - 36, height: 16))
                drawProgress(NSRect(x: rect.minX + 18, y: y + 19, width: rect.width - 36, height: 5), value: pct, color: thermHue)
                y += 32
            }
            drawMetricRow("CPU", value: s.sensors.cpuTempC.map { "\(fmt($0, 1))\u{2009}°C" } ?? "—", dot: nil,
                          rect: NSRect(x: rect.minX + 18, y: y, width: (rect.width - 36) / 2 - 16, height: 16))
            drawMetricRow("GPU", value: s.sensors.gpuTempC.map { "\(fmt($0, 1))\u{2009}°C" } ?? "—", dot: nil,
                          rect: NSRect(x: rect.midX + 6, y: y, width: (rect.width - 36) / 2 - 6, height: 16))
            let note = allOff ? S.fanNoteIdle : S.fanNoteLive
            drawText(note, in: NSRect(x: rect.minX + 18, y: rect.maxY - 26, width: rect.width - 36, height: 16),
                     size: 10.5, weight: .regular, color: textTertiary)
        } else {
            // No fan hardware exposed — fall back to an honest thermal panel.
            let hot = [s.sensors.cpuTempC, s.sensors.gpuTempC].compactMap { $0 }.max()
            drawNumberUnit(hot.map { fmt($0, 1) } ?? "—", unit: "\u{2009}°C", numberFont: heroFont(30), unitFont: tabFont(14, .medium),
                           numberColor: hot.map { tempColor($0) } ?? textTertiary, unitColor: textTertiary, at: NSPoint(x: rect.minX + 18, y: rect.minY + 46))
            drawMetricRow("CPU", value: s.sensors.cpuTempC.map { "\(fmt($0, 1))\u{2009}°C" } ?? "—", dot: thermHue,
                          rect: NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 16))
            drawMetricRow("GPU", value: s.sensors.gpuTempC.map { "\(fmt($0, 1))\u{2009}°C" } ?? "—", dot: thermHue,
                          rect: NSRect(x: rect.minX + 18, y: rect.minY + 114, width: rect.width - 36, height: 16))
            drawMetricRow(S.fanStatus, value: S.thermalText(s.thermalState), dot: thermalColor(s.thermalState),
                          rect: NSRect(x: rect.minX + 18, y: rect.minY + 136, width: rect.width - 36, height: 16), valueColor: thermalColor(s.thermalState))
            drawText(S.fanNoneNote, in: NSRect(x: rect.minX + 18, y: rect.maxY - 26, width: rect.width - 36, height: 16),
                     size: 10.5, weight: .regular, color: textTertiary)
        }
    }

    private func drawMemory(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        drawSectionTitle(S.titleRAM, subtitle: S.subRAM, rect: rect, glyph: .ram)
        let usedParts = bytesParts(s.memory.used)
        drawNumberUnit(usedParts.0, unit: usedParts.1, numberFont: heroFont(30), unitFont: tabFont(14, .medium),
                       numberColor: ramHue, unitColor: textTertiary, at: NSPoint(x: rect.minX + 18, y: rect.minY + 46),
                       secondary: "/ \(formatBytes(s.memory.total))", secondaryColor: textTertiary)
        drawProgress(NSRect(x: rect.minX + 18, y: rect.minY + 90, width: rect.width - 36, height: 8),
                     value: s.memory.ratio, color: s.memory.ratio > 0.85 ? warn : ramHue)

        // Existing vitals kept, condensed into one labelled row.
        let triW = (rect.width - 36) / 3
        drawTriple([(S.memPressure, "\(Int(round(s.memory.ratio * 100)))%", s.memory.ratio > 0.80 ? warn : textPrimary),
                    ("Swap", s.memory.swapUsed.flatMap { $0 > 0 ? formatBytes($0) : nil } ?? "0", textPrimary),
                    (S.memFree, formatBytes(s.memory.free), textPrimary)],
                   x: rect.minX + 18, y: rect.minY + 110, cellWidth: triW)

        drawText(S.memTop3, in: NSRect(x: rect.minX + 18, y: rect.minY + 144, width: rect.width - 36, height: 14),
                 size: 10.5, weight: .regular, color: textTertiary)
        var y = rect.minY + 164
        if s.topMemoryApps.isEmpty {
            drawText(S.measuring, in: NSRect(x: rect.minX + 18, y: y, width: rect.width - 36, height: 16), size: 12, weight: .regular, color: textTertiary)
        }
        for app in s.topMemoryApps.prefix(3) {
            drawMetricRow(app.name, value: formatBytes(app.rss), dot: ramHue,
                          rect: NSRect(x: rect.minX + 18, y: y, width: rect.width - 36, height: 16))
            y += 22
        }
    }

    private func drawNetwork(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        drawSectionTitle(S.titleNet, subtitle: S.subNet, rect: rect, glyph: .net)
        let down = rateParts(s.network.downPerSecond)
        let up = rateParts(s.network.upPerSecond)
        drawArrowRate("↓", number: down.0, unit: down.1, color: netHue, at: NSPoint(x: rect.minX + 18, y: rect.minY + 46))
        drawArrowRate("↑", number: up.0, unit: up.1, color: textPrimary, at: NSPoint(x: rect.midX + 6, y: rect.minY + 46))
        drawSparkline(netHistory, rect: NSRect(x: rect.minX + 18, y: rect.minY + 88, width: rect.width - 36, height: 38), hue: netHue)

        drawText(S.netTop3, in: NSRect(x: rect.minX + 18, y: rect.minY + 138, width: rect.width - 36, height: 14),
                 size: 10.5, weight: .regular, color: textTertiary)
        var y = rect.minY + 158
        let apps = s.networkApps.prefix(3)
        if apps.isEmpty {
            drawText(S.netNone, in: NSRect(x: rect.minX + 18, y: y, width: rect.width - 36, height: 16), size: 12, weight: .regular, color: textSecondary)
        }
        for app in apps {
            drawText(app.name, in: NSRect(x: rect.minX + 18, y: y, width: rect.width * 0.42, height: 16),
                     font: NSFont.systemFont(ofSize: 12, weight: .regular), color: textPrimary)
            let value = "↓\(shortRate(app.downPerSecond)) ↑\(shortRate(app.upPerSecond))"
            drawText(value, in: NSRect(x: rect.midX - 20, y: y, width: rect.width / 2 + 2, height: 16),
                     font: tabFont(12, .medium), color: textSecondary, align: .right)
            y += 22
        }
    }

    private func drawStorage(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        drawSectionTitle(S.titleStorage, subtitle: S.subStorage, rect: rect, glyph: .disk)

        guard let st = s.storage, st.total > 0 else {
            drawText(S.measuring, in: NSRect(x: rect.minX + 18, y: rect.minY + 60, width: rect.width - 36, height: 20), size: 14, weight: .regular, color: textTertiary)
            return
        }
        let freeParts = bytesParts(st.free)
        drawNumberUnit(freeParts.0, unit: freeParts.1, numberFont: heroFont(30), unitFont: tabFont(14, .medium),
                       numberColor: diskHue, unitColor: textTertiary, at: NSPoint(x: rect.minX + 18, y: rect.minY + 46),
                       secondary: S.storFreeOfTotal(formatBytes(st.total)), secondaryColor: textTertiary)

        let total = Double(st.total)
        let segs: [(Double, NSColor)] = [
            (Double(st.systemUsed) / total, storSystem),
            (Double(st.dataUsed) / total, storData),
            (Double(st.otherUsed) / total, storOther),
            (Double(st.free) / total, trackIdle)
        ]
        drawSegmentedBar(rect: NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 12), segments: segs)

        let ly = rect.minY + 118
        drawLegend(S.storSystem, value: formatBytes(st.systemUsed), color: storSystem, x: rect.minX + 18, y: ly, width: rect.width - 36)
        drawLegend(S.storData, value: formatBytes(st.dataUsed), color: storData, x: rect.minX + 18, y: ly + 22, width: rect.width - 36)
        drawLegend(S.storOther, value: formatBytes(st.otherUsed), color: storOther, x: rect.minX + 18, y: ly + 44, width: rect.width - 36)
        drawLegend(S.storFree, value: formatBytes(st.free), color: trackIdle, x: rect.minX + 18, y: ly + 66, width: rect.width - 36)
    }

    private func drawBattery(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        drawSectionTitle(S.titleBattery, subtitle: S.batteryStateText(s.battery.state), rect: rect, glyph: .battery)
        let percent = s.battery.percent ?? 0
        drawNumberUnit(s.battery.percent.map { "\(Int(round($0 * 100)))" } ?? "—", unit: "%",
                       numberFont: heroFont(30), unitFont: tabFont(14, .medium),
                       numberColor: batteryColor(percent), unitColor: textTertiary, at: NSPoint(x: rect.minX + 18, y: rect.minY + 46))
        drawProgress(NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 8), value: percent, color: batteryColor(percent))
        drawMetricRow(S.batPower, value: s.battery.watts.map { "\(fmt($0, 1)) W" } ?? "—", dot: nil,
                      rect: NSRect(x: rect.minX + 18, y: rect.minY + 114, width: rect.width - 36, height: 16))
        drawMetricRow(S.batAdapter, value: s.battery.adapterWatts.map { "\(Int(round($0))) W" } ?? "—", dot: nil,
                      rect: NSRect(x: rect.minX + 18, y: rect.minY + 136, width: rect.width - 36, height: 16))
        drawMetricRow(S.batCycles, value: s.battery.cycles.map(String.init) ?? "—", dot: nil,
                      rect: NSRect(x: rect.minX + 18, y: rect.minY + 158, width: rect.width - 36, height: 16))
    }

    private func drawAI(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        drawSectionTitle(S.titleAI, subtitle: S.subAI, rect: rect, glyph: .ai)
        if s.aiUsage.hasAny {
            drawAIEntry(name: "Codex", tool: s.aiUsage.codex, y: rect.minY + 58, rect: rect, color: cpuHue)
            drawAIEntry(name: "Claude", tool: s.aiUsage.claude, y: rect.minY + 132, rect: rect, color: chANE)
        } else {
            drawText(S.aiNone, in: NSRect(x: rect.minX + 18, y: rect.minY + 60, width: rect.width - 36, height: 22),
                     size: 15, weight: .medium, color: textPrimary)
            drawText(S.aiNoneCaption, in: NSRect(x: rect.minX + 18, y: rect.minY + 88, width: rect.width - 36, height: 16),
                     size: 11, weight: .regular, color: textTertiary)
        }
    }

    private func drawAIEntry(name: String, tool: AIToolUsage, y: CGFloat, rect: NSRect, color: NSColor) {
        let dot = NSBezierPath(ovalIn: NSRect(x: rect.minX + 18, y: y + 5, width: 6, height: 6))
        color.setFill(); dot.fill()
        drawText(name, in: NSRect(x: rect.minX + 32, y: y, width: 120, height: 16), font: NSFont.systemFont(ofSize: 12.5, weight: .medium), color: textPrimary)
        drawText("CPU \(fmt(tool.cpu, 1)) %", in: NSRect(x: rect.midX, y: y, width: rect.width / 2 - 18, height: 16),
                 font: tabFont(12.5, .medium), color: textSecondary, align: .right)
        // Extra dimensions: memory, helper-process count, and how long the app has been running.
        let detail = S.aiDetail(formatBytes(tool.memory), tool.processes, S.uptime(tool.uptimeSeconds))
        drawText(detail, in: NSRect(x: rect.minX + 32, y: y + 19, width: rect.width - 50, height: 15),
                 font: tabFont(11, .regular), color: textTertiary)
        drawProgress(NSRect(x: rect.minX + 18, y: y + 40, width: rect.width - 36, height: 6), value: min(1, tool.cpu / 100), color: color)
    }

    private func drawProcesses(_ s: MetricsSnapshot, rect: NSRect) {
        drawCard(rect)
        drawSectionTitle(S.titleProc, subtitle: S.subProc, rect: rect, glyph: .proc)
        let items = Array(s.topProcesses.prefix(5))
        let maxCPU = max(0.1, items.map { $0.cpu }.max() ?? 0.1)
        var y = rect.minY + 50
        for item in items {
            drawText(item.name, in: NSRect(x: rect.minX + 18, y: y, width: rect.width - 92, height: 16),
                     font: NSFont.systemFont(ofSize: 12, weight: .regular), color: textPrimary)
            drawText("\(fmt(item.cpu, 1)) %", in: NSRect(x: rect.maxX - 70, y: y, width: 52, height: 16),
                     font: tabFont(12, .medium), color: procHue, align: .right)
            let track = NSRect(x: rect.minX + 18, y: y + 19, width: rect.width - 36, height: 4)
            let bg = NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2)
            NSColor(white: 1, alpha: 0.07).setFill(); bg.fill()
            let w = max(4, track.width * CGFloat(min(1, item.cpu / maxCPU)))
            let fg = NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: w, height: track.height), xRadius: 2, yRadius: 2)
            procHue.setFill(); fg.fill()
            y += 29
        }
    }

    // MARK: Chrome helpers

    private func drawCard(_ rect: NSRect, radius: CGFloat = 16) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        cardFill.setFill()
        path.fill()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        cardBorder.setStroke(); border.lineWidth = 1; border.stroke()
        let hi = NSBezierPath()
        hi.move(to: NSPoint(x: rect.minX + radius, y: rect.minY + 0.75))
        hi.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY + 0.75))
        cardTopHi.setStroke(); hi.lineWidth = 1; hi.stroke()
    }

    private enum Glyph { case cpu, power, ram, fan, net, battery, disk, ai, proc }

    private func drawSectionTitle(_ title: String, subtitle: String, rect: NSRect, glyph: Glyph) {
        drawGlyph(glyph, in: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: 14, height: 14), color: textTertiary)
        drawText(title, in: NSRect(x: rect.minX + 40, y: rect.minY + 13, width: rect.width - 58, height: 18), size: 13, weight: .semibold, color: textSecondary)
        drawText(subtitle, in: NSRect(x: rect.minX + 40, y: rect.minY + 31, width: rect.width - 58, height: 15), size: 11, weight: .regular, color: textTertiary)
    }

    private func drawGlyph(_ glyph: Glyph, in r: NSRect, color: NSColor) {
        color.setStroke()
        let lw: CGFloat = 1.3
        func p() -> NSBezierPath { let path = NSBezierPath(); path.lineWidth = lw; path.lineJoinStyle = .round; path.lineCapStyle = .round; return path }
        switch glyph {
        case .cpu:
            let body = NSBezierPath(roundedRect: r.insetBy(dx: 3, dy: 3), xRadius: 2, yRadius: 2)
            body.lineWidth = lw; body.stroke()
            let pins = p()
            for f in [0.35, 0.65] {
                pins.move(to: NSPoint(x: r.minX + r.width * f, y: r.minY)); pins.line(to: NSPoint(x: r.minX + r.width * f, y: r.minY + 3))
                pins.move(to: NSPoint(x: r.minX + r.width * f, y: r.maxY - 3)); pins.line(to: NSPoint(x: r.minX + r.width * f, y: r.maxY))
                pins.move(to: NSPoint(x: r.minX, y: r.minY + r.height * f)); pins.line(to: NSPoint(x: r.minX + 3, y: r.minY + r.height * f))
                pins.move(to: NSPoint(x: r.maxX - 3, y: r.minY + r.height * f)); pins.line(to: NSPoint(x: r.maxX, y: r.minY + r.height * f))
            }
            pins.stroke()
        case .power:
            let bolt = p()
            bolt.move(to: NSPoint(x: r.minX + 8, y: r.minY + 1)); bolt.line(to: NSPoint(x: r.minX + 4, y: r.minY + 8))
            bolt.line(to: NSPoint(x: r.minX + 7, y: r.minY + 8)); bolt.line(to: NSPoint(x: r.minX + 6, y: r.maxY - 1))
            bolt.line(to: NSPoint(x: r.minX + 11, y: r.minY + 6)); bolt.line(to: NSPoint(x: r.minX + 8, y: r.minY + 6)); bolt.close(); bolt.stroke()
        case .ram:
            let body = NSBezierPath(roundedRect: NSRect(x: r.minX + 1, y: r.minY + 3, width: r.width - 2, height: r.height - 7), xRadius: 1.5, yRadius: 1.5)
            body.lineWidth = lw; body.stroke()
            let inner = p()
            for f in [0.32, 0.5, 0.68] { inner.move(to: NSPoint(x: r.minX + r.width * f, y: r.minY + 5)); inner.line(to: NSPoint(x: r.minX + r.width * f, y: r.maxY - 6)) }
            inner.move(to: NSPoint(x: r.minX + 3.5, y: r.maxY - 4)); inner.line(to: NSPoint(x: r.minX + 3.5, y: r.maxY - 1))
            inner.move(to: NSPoint(x: r.maxX - 3.5, y: r.maxY - 4)); inner.line(to: NSPoint(x: r.maxX - 3.5, y: r.maxY - 1)); inner.stroke()
        case .fan:
            let hub = NSBezierPath(ovalIn: NSRect(x: r.midX - 1.4, y: r.midY - 1.4, width: 2.8, height: 2.8))
            hub.lineWidth = lw; hub.stroke()
            let blades = p()
            for k in 0..<3 {
                let a = CGFloat(k) * 2 * .pi / 3
                blades.move(to: NSPoint(x: r.midX, y: r.midY))
                blades.appendArc(withCenter: NSPoint(x: r.midX + 3 * cos(a), y: r.midY + 3 * sin(a)), radius: 3, startAngle: 0, endAngle: 360)
            }
            blades.stroke()
        case .net:
            let arcs = p()
            let cx = r.minX + 2, cy = r.maxY - 2
            for radius in [3.0, 6.0, 9.0] { arcs.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: radius, startAngle: 0, endAngle: 90) }
            arcs.stroke()
        case .battery:
            let body = NSBezierPath(roundedRect: NSRect(x: r.minX + 1, y: r.minY + 4, width: r.width - 4, height: r.height - 8), xRadius: 1.6, yRadius: 1.6)
            body.lineWidth = lw; body.stroke()
            let nub = NSBezierPath(roundedRect: NSRect(x: r.maxX - 2.5, y: r.midY - 2, width: 2, height: 4), xRadius: 1, yRadius: 1)
            nub.lineWidth = lw; nub.stroke()
        case .disk:
            let top = NSBezierPath(ovalIn: NSRect(x: r.minX + 1.5, y: r.minY + 2, width: r.width - 3, height: 4))
            top.lineWidth = lw; top.stroke()
            let sides = p()
            sides.move(to: NSPoint(x: r.minX + 1.5, y: r.minY + 4)); sides.line(to: NSPoint(x: r.minX + 1.5, y: r.maxY - 4))
            sides.appendArc(withCenter: NSPoint(x: r.midX, y: r.maxY - 4), radius: (r.width - 3) / 2, startAngle: 180, endAngle: 360, clockwise: false)
            sides.move(to: NSPoint(x: r.maxX - 1.5, y: r.maxY - 4)); sides.line(to: NSPoint(x: r.maxX - 1.5, y: r.minY + 4)); sides.stroke()
        case .ai:
            let chev = p()
            chev.move(to: NSPoint(x: r.minX + 2, y: r.minY + 3)); chev.line(to: NSPoint(x: r.minX + 6, y: r.midY)); chev.line(to: NSPoint(x: r.minX + 2, y: r.maxY - 3))
            chev.move(to: NSPoint(x: r.midX + 1, y: r.maxY - 2)); chev.line(to: NSPoint(x: r.maxX - 1, y: r.maxY - 2)); chev.stroke()
        case .proc:
            let lines = p()
            let widths: [CGFloat] = [r.width - 2, r.width - 5, r.width - 3]
            for (i, w) in widths.enumerated() {
                let yy = r.minY + 2 + CGFloat(i) * ((r.height - 4) / 2)
                lines.move(to: NSPoint(x: r.minX, y: yy)); lines.line(to: NSPoint(x: r.minX + w, y: yy))
            }
            lines.stroke()
        }
    }

    // MARK: Primitive drawing

    private func drawNumberUnit(_ number: String, unit: String, numberFont: NSFont, unitFont: NSFont,
                                numberColor: NSColor, unitColor: NSColor, at origin: NSPoint,
                                secondary: String? = nil, secondaryColor: NSColor? = nil) {
        let lineH = numberFont.ascender - numberFont.descender + 6
        let nWidth = textWidth(number, font: numberFont)
        drawText(number, in: NSRect(x: origin.x, y: origin.y, width: nWidth + 6, height: lineH), font: numberFont, color: numberColor)
        let unitX = origin.x + nWidth + 5
        let unitY = origin.y + (numberFont.ascender - unitFont.ascender)
        let uWidth = textWidth(unit, font: unitFont)
        let unitLineH = unitFont.ascender - unitFont.descender + 6
        drawText(unit, in: NSRect(x: unitX, y: unitY, width: uWidth + 6, height: unitLineH), font: unitFont, color: unitColor)
        if let secondary, let secondaryColor {
            let sX = unitX + uWidth + 7
            let sWidth = textWidth(secondary, font: unitFont)
            drawText(secondary, in: NSRect(x: sX, y: unitY, width: sWidth + 12, height: unitLineH), font: unitFont, color: secondaryColor)
        }
    }

    private func drawArrowRate(_ arrow: String, number: String, unit: String, color: NSColor, at origin: NSPoint) {
        let numFont = heroFont(22)
        let unitFont = tabFont(12, .medium)
        drawText(arrow, in: NSRect(x: origin.x, y: origin.y + 6, width: 16, height: 22), font: NSFont.systemFont(ofSize: 13, weight: .regular), color: textTertiary)
        let numX = origin.x + 16
        let nWidth = textWidth(number, font: numFont)
        drawText(number, in: NSRect(x: numX, y: origin.y, width: nWidth + 6, height: 30), font: numFont, color: color)
        drawText(unit, in: NSRect(x: numX + nWidth + 4, y: origin.y + (numFont.ascender - unitFont.ascender), width: 56, height: 18), font: unitFont, color: textTertiary)
    }

    private func drawTriple(_ cells: [(String, String, NSColor)], x: CGFloat, y: CGFloat, cellWidth: CGFloat) {
        for (i, cell) in cells.enumerated() {
            let cx = x + CGFloat(i) * cellWidth
            drawText(cell.0, in: NSRect(x: cx, y: y, width: cellWidth, height: 14), size: 10.5, weight: .regular, color: textTertiary)
            drawText(cell.1, in: NSRect(x: cx, y: y + 13, width: cellWidth, height: 16), font: tabFont(13, .medium), color: cell.2)
        }
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, align: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineBreakMode = .byTruncatingTail
        text.draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, align: NSTextAlignment = .left) {
        drawText(text, in: rect, font: NSFont.systemFont(ofSize: size, weight: weight), color: color, align: align)
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func drawProgress(_ rect: NSRect, value: Double, color: NSColor) {
        let bg = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        trackIdle.setFill(); bg.fill()
        let clamped = max(0, min(1, value))
        guard clamped > 0 else { return }
        let w = max(rect.height, rect.width * CGFloat(clamped))
        let fg = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: min(rect.width, w), height: rect.height), xRadius: rect.height / 2, yRadius: rect.height / 2)
        color.setFill(); fg.fill()
    }

    private func drawStackBar(rect: NSRect, segments: [(Double, NSColor)]) {
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        clip.addClip()
        trackIdle.setFill(); clip.fill()
        var x = rect.minX
        for (index, segment) in segments.enumerated() {
            let width = rect.width * CGFloat(max(0, min(1, segment.0)))
            guard width > 0.5 else { continue }
            let gap: CGFloat = (index > 0 && index < segments.count - 1) ? 1.5 : 0
            let seg = NSRect(x: x + gap, y: rect.minY, width: max(0, width - gap), height: rect.height)
            segment.1.setFill(); NSBezierPath(rect: seg).fill()
            x += width
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSegmentedBar(rect: NSRect, segments: [(Double, NSColor)]) {
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        clip.addClip()
        trackIdle.setFill(); clip.fill()
        var x = rect.minX
        for segment in segments {
            let width = rect.width * CGFloat(max(0, min(1, segment.0)))
            guard width > 0.5 else { continue }
            let seg = NSRect(x: x, y: rect.minY, width: width, height: rect.height)
            segment.1.setFill(); NSBezierPath(rect: seg.insetBy(dx: 0.4, dy: 0)).fill()
            x += width
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSparkline(_ values: [Double], rect: NSRect, hue: NSColor) {
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: rect.minX, y: rect.maxY - 0.5))
        baseline.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 0.5))
        textQuaternary.setStroke(); baseline.lineWidth = 0.5; baseline.stroke()
        guard values.count > 1 else { return }
        let step = rect.width / CGFloat(values.count - 1)
        let path = NSBezierPath()
        let fillPath = NSBezierPath()
        var lastPoint = NSPoint(x: rect.minX, y: rect.maxY)
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) * step
            let y = rect.maxY - CGFloat(max(0, min(1, value))) * (rect.height - 2)
            let pt = NSPoint(x: x, y: y)
            if index == 0 { path.move(to: pt); fillPath.move(to: NSPoint(x: x, y: rect.maxY)); fillPath.line(to: pt) }
            else { path.line(to: pt); fillPath.line(to: pt) }
            lastPoint = pt
        }
        fillPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY)); fillPath.close()
        // Solid translucent fill instead of a gradient (gradients are GPU-expensive per frame).
        hue.withAlphaComponent(0.13).setFill()
        fillPath.fill()
        hue.setStroke(); path.lineWidth = 1.5; path.lineJoinStyle = .round; path.lineCapStyle = .round; path.stroke()
        let dot = NSBezierPath(ovalIn: NSRect(x: lastPoint.x - 2, y: lastPoint.y - 2, width: 4, height: 4))
        hue.setFill(); dot.fill()
    }

    private func drawLegend(_ name: String, value: String, color: NSColor, x: CGFloat, y: CGFloat, width: CGFloat) {
        let swatch = NSBezierPath(roundedRect: NSRect(x: x, y: y + 2, width: 10, height: 10), xRadius: 3, yRadius: 3)
        color.setFill(); swatch.fill()
        drawText(name, in: NSRect(x: x + 18, y: y, width: 90, height: 16), size: 11.5, weight: .regular, color: textSecondary)
        drawText(value, in: NSRect(x: x + width - 130, y: y, width: 130, height: 16), font: tabFont(11.5, .medium), color: textTertiary, align: .right)
    }

    private func drawMetricRow(_ name: String, value: String, dot: NSColor?, rect: NSRect, valueColor: NSColor? = nil) {
        var labelX = rect.minX
        if let dot {
            let d = NSBezierPath(ovalIn: NSRect(x: rect.minX, y: rect.midY - 2.5, width: 5, height: 5))
            dot.setFill(); d.fill()
            labelX = rect.minX + 12
        }
        drawText(name, in: NSRect(x: labelX, y: rect.minY, width: rect.width * 0.5, height: rect.height),
                 font: NSFont.systemFont(ofSize: 12, weight: .regular), color: textSecondary)
        drawText(value, in: NSRect(x: rect.midX - 12, y: rect.minY, width: rect.width / 2 + 12, height: rect.height),
                 font: tabFont(12, .medium), color: valueColor ?? textPrimary, align: .right)
    }

    // MARK: Color tokens

    private var bgTop: NSColor { NSColor(red: 0.075, green: 0.080, blue: 0.094, alpha: 1) }
    private var bgBottom: NSColor { NSColor(red: 0.047, green: 0.050, blue: 0.060, alpha: 1) }
    private var cardFill: NSColor { NSColor(red: 0.140, green: 0.146, blue: 0.160, alpha: 1) }
    private var cardFillTop: NSColor { NSColor(red: 0.156, green: 0.162, blue: 0.176, alpha: 1) }
    private var cardBorder: NSColor { NSColor(white: 1, alpha: 0.075) }
    private var cardTopHi: NSColor { NSColor(white: 1, alpha: 0.13) }
    private var textPrimary: NSColor { NSColor(red: 0.955, green: 0.960, blue: 0.970, alpha: 1) }
    private var textSecondary: NSColor { NSColor(red: 0.620, green: 0.635, blue: 0.665, alpha: 1) }
    private var textTertiary: NSColor { NSColor(red: 0.430, green: 0.445, blue: 0.475, alpha: 1) }
    private var textQuaternary: NSColor { NSColor(red: 0.300, green: 0.312, blue: 0.340, alpha: 1) }
    private var accent: NSColor { NSColor(red: 0.98, green: 0.74, blue: 0.30, alpha: 1) }
    private var cpuHue: NSColor { NSColor(red: 0.40, green: 0.68, blue: 0.92, alpha: 1) }
    private var pwrHue: NSColor { NSColor(red: 0.56, green: 0.78, blue: 0.50, alpha: 1) }
    private var ramHue: NSColor { NSColor(red: 0.70, green: 0.62, blue: 0.90, alpha: 1) }
    private var netHue: NSColor { NSColor(red: 0.45, green: 0.72, blue: 0.88, alpha: 1) }
    private var diskHue: NSColor { NSColor(red: 0.60, green: 0.64, blue: 0.72, alpha: 1) }
    private var thermHue: NSColor { NSColor(red: 0.55, green: 0.72, blue: 0.80, alpha: 1) }
    private var procHue: NSColor { NSColor(red: 0.46, green: 0.62, blue: 0.90, alpha: 1) }
    private var chUser: NSColor { cpuHue }
    private var chSystem: NSColor { NSColor(red: 0.90, green: 0.55, blue: 0.42, alpha: 1) }
    private var chGPU: NSColor { NSColor(red: 0.92, green: 0.52, blue: 0.62, alpha: 1) }
    private var chANE: NSColor { NSColor(red: 0.66, green: 0.56, blue: 0.92, alpha: 1) }
    private var chDRAM: NSColor { pwrHue }
    private var trackIdle: NSColor { NSColor(white: 1, alpha: 0.10) }
    private var storSystem: NSColor { NSColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1) }
    private var storData: NSColor { cpuHue }
    private var storOther: NSColor { NSColor(red: 0.66, green: 0.56, blue: 0.92, alpha: 1) }
    private var ok: NSColor { NSColor(red: 0.46, green: 0.80, blue: 0.54, alpha: 1) }
    private var warn: NSColor { NSColor(red: 0.96, green: 0.72, blue: 0.36, alpha: 1) }
    private var crit: NSColor { NSColor(red: 0.93, green: 0.45, blue: 0.42, alpha: 1) }

    // MARK: Fonts

    private func heroFont(_ size: CGFloat) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        if let rounded = base.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: rounded, size: size) ?? base }
        return base
    }

    private func tabFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Semantic colors

    private func thermalColor(_ value: Thermal) -> NSColor {
        switch value {
        case .nominal: return ok
        case .fair: return warn
        case .serious: return warn
        case .critical: return crit
        case .unknown: return textTertiary
        }
    }

    private func tempColor(_ celsius: Double) -> NSColor {
        if celsius >= 80 { return crit }
        if celsius >= 60 { return warn }
        return thermHue
    }

    private func batteryColor(_ value: Double) -> NSColor {
        if value < 0.18 { return crit }
        if value < 0.35 { return warn }
        return ok
    }

    // MARK: Formatting

    private func fmt(_ value: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", value) }

    private func powerStr(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value < 0.05 { return "0.0 W" }
        return "\(fmt(value, 1)) W"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let parts = bytesParts(bytes)
        return "\(parts.0) \(parts.1)"
    }

    private func bytesParts(_ bytes: UInt64) -> (String, String) {
        let value = Double(bytes)
        let tb = 1024.0 * 1024.0 * 1024.0 * 1024.0
        let gb = 1024.0 * 1024.0 * 1024.0
        let mb = 1024.0 * 1024.0
        if value >= tb { return (fmt(value / tb, 2), "TB") }
        if value >= gb { let g = value / gb; return (g < 100 ? fmt(g, 1) : fmt(g, 0), "GB") }
        if value >= mb { return (fmt(value / mb, 0), "MB") }
        return ("\(Int(value / 1024.0))", "KB")
    }

    private func rateParts(_ bytesPerSecond: Double) -> (String, String) {
        let mb = 1024.0 * 1024.0, kb = 1024.0
        if bytesPerSecond >= mb { return (fmt(bytesPerSecond / mb, 1), "MB/s") }
        if bytesPerSecond >= kb { return ("\(Int(bytesPerSecond / kb))", "KB/s") }
        return ("\(Int(bytesPerSecond))", "B/s")
    }

    private func shortRate(_ bytesPerSecond: Double) -> String {
        let mb = 1024.0 * 1024.0, kb = 1024.0
        if bytesPerSecond >= mb { return "\(fmt(bytesPerSecond / mb, 1))M" }
        if bytesPerSecond >= kb { return "\(Int(bytesPerSecond / kb))K" }
        return "\(Int(bytesPerSecond))B"
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let dashboard = DashboardView(frame: .zero)
    private let provider = MetricsProvider()
    private var timer: Timer?
    private var isSampling = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = S.appName
        window.minSize = NSSize(width: 880, height: 800)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.075, green: 0.080, blue: 0.094, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        dashboard.wantsLayer = true
        dashboard.layerContentsRedrawPolicy = .never
        window.contentView = dashboard
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }

    private func tick() {
        guard !isSampling else { return }
        isSampling = true
        DispatchQueue.global(qos: .utility).async { [provider, dashboard] in
            let snapshot = provider.snapshot()
            DispatchQueue.main.async {
                dashboard.update(snapshot)
                self.isSampling = false
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
