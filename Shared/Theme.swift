#if canImport(UIKit)
import UIKit

struct KBTheme {
    let id: String
    let name: String
    let background: UIColor
    let key: UIColor
    let keyText: UIColor
    let special: UIColor
    let specialText: UIColor
    let accent: UIColor
    let bar: UIColor
    let hint: UIColor
    let shadow: UIColor
    let dark: Bool
    var gradient: [UIColor]? = nil

    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    static let all: [KBTheme] = [
        KBTheme(id: "swift", name: "Swift Blue", background: hex(0x0B1220), key: hex(0x1B2740), keyText: .white, special: hex(0x111A2E), specialText: hex(0xC7D2FE), accent: hex(0x3B6CFF), bar: hex(0x0B1220), hint: hex(0x8FB3FF), shadow: hex(0x000000, 0.5), dark: true, gradient: [hex(0x0B1220), hex(0x1E1B4B)]),
        KBTheme(id: "light", name: "Light", background: hex(0xD1D5DB), key: .white, keyText: hex(0x111827), special: hex(0xAEB4BE), specialText: hex(0x111827), accent: hex(0x2563FF), bar: hex(0xD1D5DB), hint: hex(0x6B7280), shadow: hex(0x000000, 0.3), dark: false),
        KBTheme(id: "dark", name: "Dark", background: hex(0x1C1C1E), key: hex(0x48484A), keyText: .white, special: hex(0x2C2C2E), specialText: .white, accent: hex(0x0A84FF), bar: hex(0x1C1C1E), hint: hex(0x9CA3AF), shadow: hex(0x000000, 0.6), dark: true),
        KBTheme(id: "amoled", name: "AMOLED Black", background: .black, key: hex(0x161616), keyText: .white, special: hex(0x0A0A0A), specialText: hex(0xD1D5DB), accent: hex(0x22C55E), bar: .black, hint: hex(0x22C55E), shadow: .clear, dark: true),
        KBTheme(id: "lanka", name: "Lanka Gold", background: hex(0x3B0A0A), key: hex(0x7F1D1D), keyText: hex(0xFDE68A), special: hex(0x581212), specialText: hex(0xFDE68A), accent: hex(0xF59E0B), bar: hex(0x3B0A0A), hint: hex(0xFBBF24), shadow: hex(0x000000, 0.5), dark: true, gradient: [hex(0x450A0A), hex(0x78350F)]),
        KBTheme(id: "ocean", name: "Ocean", background: hex(0x083344), key: hex(0x0E7490), keyText: .white, special: hex(0x155E75), specialText: hex(0xCFFAFE), accent: hex(0x22D3EE), bar: hex(0x083344), hint: hex(0xA5F3FC), shadow: hex(0x000000, 0.4), dark: true, gradient: [hex(0x083344), hex(0x1E3A8A)]),
        KBTheme(id: "purple", name: "Purple Night", background: hex(0x1E1033), key: hex(0x3B2366), keyText: .white, special: hex(0x2B1A4F), specialText: hex(0xE9D5FF), accent: hex(0xA855F7), bar: hex(0x1E1033), hint: hex(0xD8B4FE), shadow: hex(0x000000, 0.5), dark: true, gradient: [hex(0x1E1033), hex(0x4C1D95)]),
        KBTheme(id: "mint", name: "Mint", background: hex(0xD1FAE5), key: .white, keyText: hex(0x064E3B), special: hex(0xA7F3D0), specialText: hex(0x064E3B), accent: hex(0x059669), bar: hex(0xD1FAE5), hint: hex(0x059669), shadow: hex(0x000000, 0.2), dark: false),
        KBTheme(id: "pink", name: "Sakura", background: hex(0xFCE7F3), key: .white, keyText: hex(0x831843), special: hex(0xFBCFE8), specialText: hex(0x831843), accent: hex(0xDB2777), bar: hex(0xFCE7F3), hint: hex(0xDB2777), shadow: hex(0x000000, 0.2), dark: false),
        KBTheme(id: "photo", name: "My photo", background: hex(0x000000), key: hex(0xFFFFFF, 0.22), keyText: .white, special: hex(0x000000, 0.35), specialText: .white, accent: hex(0x3B6CFF), bar: hex(0x000000, 0.25), hint: hex(0xFFFFFF, 0.8), shadow: .clear, dark: true),
    ]

    static func named(_ id: String) -> KBTheme { all.first { $0.id == id } ?? all[0] }
}
#endif
