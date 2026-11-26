import Foundation
import Darwin

/// Tiny launch log for the keyboard, so a blank keyboard can be explained:
/// it records each start stage and the memory used. Shown in the app (More → Keyboard health).
enum KBDiag {
    private static var d: UserDefaults { SharedStore.shared.defaults }
    private static let stageKey = "diag.stage"

    static func mark(_ stage: String) {
        let prev = d.string(forKey: stageKey)
        // short trail of what happened (helps see exactly where a blank keyboard stopped)
        var trail = d.stringArray(forKey: "diag.trail") ?? []
        trail.append("\(stage)@\(String(format: "%.2f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)))")
        d.set(Array(trail.suffix(14)), forKey: "diag.trail")
        if stage == "load" {
            d.set(d.integer(forKey: "diag.launches") + 1, forKey: "diag.launches")
            // the previous start never reached the screen → that was a blank keyboard
            if let p = prev, p != "appear", p != "disappear" {
                d.set(d.integer(forKey: "diag.blank") + 1, forKey: "diag.blank")
                d.set("\(p) @ \(Self.fmt(d.double(forKey: "diag.stageAt")))", forKey: "diag.lastBlank")
                d.set(trail.dropLast().suffix(10).joined(separator: " → "), forKey: "diag.blankTrail")
            }
        }
        d.set(stage, forKey: stageKey)
        d.set(Date().timeIntervalSince1970, forKey: "diag.stageAt")
        if stage == "appear" || stage == "disappear" {
            let mb = memoryMB()
            d.set(mb, forKey: "diag.mem")
            if mb > d.double(forKey: "diag.memMax") { d.set(mb, forKey: "diag.memMax") }
        }
        if stage == "appear", let start = d.object(forKey: "diag.loadAt") as? Double {
            d.set(Date().timeIntervalSince1970 - start, forKey: "diag.startSec")
        }
        if stage == "load" { d.set(Date().timeIntervalSince1970, forKey: "diag.loadAt") }
    }

    // MARK: crash catcher
    private static var crashFD: Int32 = -1
    static var crashFile: URL { SharedStore.shared.containerURL.appendingPathComponent("kb-crash.txt") }

    /// Records the reason + call stack if the keyboard crashes, so the next launch can show it.
    static func installCrashCatcher() {
        let path = crashFile.path
        if FileManager.default.fileExists(atPath: path), let txt = try? String(contentsOfFile: path), !txt.isEmpty {
            d.set(String(txt.prefix(3000)), forKey: "diag.lastCrash")
            d.set(Date().timeIntervalSince1970, forKey: "diag.lastCrashAt")
            try? FileManager.default.removeItem(atPath: path)
        }
        NSSetUncaughtExceptionHandler { e in
            let s = "EXCEPTION \(e.name.rawValue): \(e.reason ?? "")\n" + e.callStackSymbols.prefix(25).joined(separator: "\n")
            try? s.write(toFile: KBDiag.crashFile.path, atomically: false, encoding: .utf8)
        }
        crashFD = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard crashFD >= 0 else { return }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { s in
                // only async-signal-safe calls here
                let fd = KBDiag.crashFD
                var head = Array("SIGNAL \(s)\n".utf8)
                _ = write(fd, &head, head.count)
                var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 40)
                let n = backtrace(&frames, 40)
                backtrace_symbols_fd(&frames, n, fd)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    /// Everything above as plain text, to copy and send.
    static var fullReport: String {
        var out = report.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        out += "\nTrail: " + (d.stringArray(forKey: "diag.trail") ?? []).joined(separator: " → ")
        out += "\nBlank trail: " + (d.string(forKey: "diag.blankTrail") ?? "—")
        if let c = d.string(forKey: "diag.lastCrash") { out += "\nLast crash (\(fmt(d.double(forKey: "diag.lastCrashAt")))):\n" + c }
        out += "\niOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        return out
    }

    static func memoryWarning() { d.set(d.integer(forKey: "diag.memWarn") + 1, forKey: "diag.memWarn") }

    static var report: [(String, String)] {
        [("Install", (Bundle.main.object(forInfoDictionaryKey: "ALTDeviceID") != nil || hostInfo("ALTDeviceID") != nil) ? "SideStore / AltStore" : "වෙනත් (3uTools / ad-hoc)"),
         ("Bundle", String((Bundle.main.bundleIdentifier ?? "?").suffix(32))),
         ("App Group", SharedStore.shared.activeGroup.map { String($0.suffix(28)) } ?? "❌ නැහැ (app ↔ keyboard වෙන වෙනම)"),
         ("Keychain", d.object(forKey: "diag.keychain") == nil ? "—" : (d.integer(forKey: "diag.keychain") == 0 ? "✓ OK" : "❌ \(d.integer(forKey: "diag.keychain"))")),
         ("Settings backup", d.double(forKey: "diag.backupAt") > 0 ? fmt(d.double(forKey: "diag.backupAt")) : "—"),
         ("Keyboard open වුණ වාර", "\(d.integer(forKey: "diag.launches"))"),
         ("Crash", d.string(forKey: "diag.lastCrash").map { String($0.prefix(60)) + "… (\(fmt(d.double(forKey: "diag.lastCrashAt"))))" } ?? "නැහැ"),
         ("හිස්ව ආව වාර (ඇස්තමේන්තුව)", "\(d.integer(forKey: "diag.blank"))"),
         ("අන්තිම හිස් වීම", d.string(forKey: "diag.lastBlank") ?? "—"),
         ("Memory warnings", "\(d.integer(forKey: "diag.memWarn"))"),
         ("Memory දැන් / උපරිම", String(format: "%.0f MB / %.0f MB", d.double(forKey: "diag.mem"), d.double(forKey: "diag.memMax"))),
         ("පටන් ගන්න ගිය වෙලාව", String(format: "%.2f s", d.double(forKey: "diag.startSec")))]
    }
    static func reset() { for k in ["diag.trail", "diag.blankTrail", "diag.lastCrash", "diag.lastCrashAt", "diag.launches", "diag.blank", "diag.lastBlank", "diag.memWarn", "diag.mem", "diag.memMax", "diag.startSec"] { d.removeObject(forKey: k) } }

    private static func hostInfo(_ key: String) -> Any? {
        let u = Bundle.main.bundleURL
        guard u.pathExtension == "appex", let host = Bundle(url: u.deletingLastPathComponent().deletingLastPathComponent()) else { return nil }
        return host.object(forInfoDictionaryKey: key)
    }

    private static func fmt(_ t: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
        return f.string(from: Date(timeIntervalSince1970: t))
    }

    static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
