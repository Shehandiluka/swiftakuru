import Foundation

/// Tiny launch log for the keyboard, so a blank keyboard can be explained:
/// it records each start stage and the memory used. Shown in the app (More → Keyboard health).
enum KBDiag {
    private static var d: UserDefaults { SharedStore.shared.defaults }
    private static let stageKey = "diag.stage"

    static func mark(_ stage: String) {
        let prev = d.string(forKey: stageKey)
        if stage == "load" {
            d.set(d.integer(forKey: "diag.launches") + 1, forKey: "diag.launches")
            // the previous start never reached the screen → that was a blank keyboard
            if let p = prev, p != "appear", p != "disappear" {
                d.set(d.integer(forKey: "diag.blank") + 1, forKey: "diag.blank")
                d.set("\(p) @ \(Self.fmt(d.double(forKey: "diag.stageAt")))", forKey: "diag.lastBlank")
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

    static func memoryWarning() { d.set(d.integer(forKey: "diag.memWarn") + 1, forKey: "diag.memWarn") }

    static var report: [(String, String)] {
        [("Install", (Bundle.main.object(forInfoDictionaryKey: "ALTDeviceID") != nil || hostInfo("ALTDeviceID") != nil) ? "SideStore / AltStore" : "වෙනත් (3uTools / ad-hoc)"),
         ("Bundle", String((Bundle.main.bundleIdentifier ?? "?").suffix(32))),
         ("App Group", SharedStore.shared.activeGroup.map { String($0.suffix(28)) } ?? "❌ නැහැ (app ↔ keyboard වෙන වෙනම)"),
         ("Keychain", d.object(forKey: "diag.keychain") == nil ? "—" : (d.integer(forKey: "diag.keychain") == 0 ? "✓ OK" : "❌ \(d.integer(forKey: "diag.keychain"))")),
         ("Settings backup", d.double(forKey: "diag.backupAt") > 0 ? fmt(d.double(forKey: "diag.backupAt")) : "—"),
         ("Keyboard open වුණ වාර", "\(d.integer(forKey: "diag.launches"))"),
         ("හිස්ව ආව වාර (ඇස්තමේන්තුව)", "\(d.integer(forKey: "diag.blank"))"),
         ("අන්තිම හිස් වීම", d.string(forKey: "diag.lastBlank") ?? "—"),
         ("Memory warnings", "\(d.integer(forKey: "diag.memWarn"))"),
         ("Memory දැන් / උපරිම", String(format: "%.0f MB / %.0f MB", d.double(forKey: "diag.mem"), d.double(forKey: "diag.memMax"))),
         ("පටන් ගන්න ගිය වෙලාව", String(format: "%.2f s", d.double(forKey: "diag.startSec")))]
    }
    static func reset() { for k in ["diag.launches", "diag.blank", "diag.lastBlank", "diag.memWarn", "diag.mem", "diag.memMax", "diag.startSec"] { d.removeObject(forKey: k) } }

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
