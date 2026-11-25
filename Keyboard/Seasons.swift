import UIKit

/// Sri Lankan seasons & festivals: when one is near, the keyboard gets a light animation
/// (snow at Christmas, Avurudu sweets, Vesak lanterns…). The animation runs on the GPU, never takes touches
/// and never delays typing. Off switch: keyboard ⚙️ → "Season effects".
struct Season: Equatable {
    let id: String
    let greeting: String

    static let all: [String: Season] = [
        "christmas": Season(id: "christmas", greeting: "🎄 Merry Christmas! සුබ නත්තලක් වේවා!"),
        "newyear": Season(id: "newyear", greeting: "🎆 Happy New Year! සුබ නව වසරක් වේවා!"),
        "pongal": Season(id: "pongal", greeting: "🌾 Happy Thai Pongal!"),
        "independence": Season(id: "independence", greeting: "🇱🇰 සුබ නිදහස් දිනයක් වේවා!"),
        "valentine": Season(id: "valentine", greeting: "❤️ Happy Valentine's Day!"),
        "avurudu": Season(id: "avurudu", greeting: "🪔 සුබ අලුත් අවුරුද්දක් වේවා!"),
        "vesak": Season(id: "vesak", greeting: "☸️ සුබ වෙසක් මංගල්‍යයක් වේවා!"),
        "poson": Season(id: "poson", greeting: "🪷 සුබ පොසොන් මංගල්‍යයක් වේවා!"),
        "deepavali": Season(id: "deepavali", greeting: "🪔 Happy Deepavali!"),
        "eid": Season(id: "eid", greeting: "🌙 Eid Mubarak!"),
    ]
    static let previewOrder = ["christmas", "newyear", "avurudu", "vesak", "poson", "deepavali", "eid", "pongal", "independence", "valentine"]
    static let icons = ["christmas": "❄️", "newyear": "🎆", "avurudu": "🍪", "vesak": "🏮", "poson": "🪷", "deepavali": "🪔", "eid": "🌙", "pongal": "🌾", "independence": "🇱🇰", "valentine": "❤️"]

    /// Festivals on the moon calendar move every year (official Sri Lanka holiday calendar).
    /// Later years come from seasons.json in the GitHub repo (fetched once a week), so no app update is needed.
    private static let lunar: [(String, String)] = [
        ("eid", "2026-03-21"), ("vesak", "2026-05-01"), ("poson", "2026-06-29"), ("deepavali", "2026-11-08"),
        ("pongal", "2027-01-15"), ("eid", "2027-03-10"), ("vesak", "2027-05-19"), ("poson", "2027-06-18"), ("deepavali", "2027-10-28"),
    ]
    private static let windows: [String: (before: Int, after: Int)] = [
        "eid": (1, 1), "vesak": (3, 3), "poson": (1, 1), "deepavali": (2, 1), "pongal": (2, 1),
    ]

    static func current(_ now: Date = Date()) -> Season? {
        let d = SharedStore.shared.defaults
        if let p = d.string(forKey: "seasonPreview"), let s = all[p] { return s }
        guard d.bool(forKey: SharedStore.K.seasonFx) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Colombo") ?? .current
        let c = cal.dateComponents([.month, .day], from: now)
        let m = c.month ?? 0, day = c.day ?? 0
        // fixed dates
        if m == 12 && day >= 18 && day <= 26 { return all["christmas"] }
        if (m == 12 && day == 31) || (m == 1 && day == 1) { return all["newyear"] }
        if m == 2 && (day == 3 || day == 4) { return all["independence"] }
        if m == 2 && day == 14 { return all["valentine"] }
        if m == 4 && day >= 10 && day <= 16 { return all["avurudu"] }
        // moon-calendar festivals
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = cal.timeZone
        let today = cal.startOfDay(for: now)
        for (id, ds) in lunar + remote() {
            guard let date = f.date(from: ds), let w = windows[id] else { continue }
            let diff = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: today).day ?? 999
            if diff >= -w.before && diff <= w.after { return all[id] }
        }
        if m == 1 && day >= 13 && day <= 15, !(lunar + remote()).contains(where: { $0.0 == "pongal" && $0.1.hasPrefix("\(cal.component(.year, from: now))") }) { return all["pongal"] }
        return nil
    }

    // MARK: remote calendar (seasons.json)
    private static func remote() -> [(String, String)] {
        guard let arr = SharedStore.shared.defaults.array(forKey: "seasonsRemote") as? [[String]] else { return [] }
        return arr.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }
    static func refreshRemoteIfNeeded() {
        let d = SharedStore.shared.defaults
        guard Date().timeIntervalSince1970 - d.double(forKey: "seasonsFetchedAt") > 7 * 86400,
              let url = URL(string: "https://raw.githubusercontent.com/Shehandiluka/swiftakuru/main/seasons.json") else { return }
        d.set(Date().timeIntervalSince1970, forKey: "seasonsFetchedAt")
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
            let pairs = list.compactMap { e -> [String]? in
                guard let id = e["id"], let date = e["date"] else { return nil }
                return [id, date]
            }
            d.set(pairs, forKey: "seasonsRemote")
        }.resume()
    }
}

/// The falling / floating animation over the keys.
final class SeasonEffectView: UIView {
    private let emitter = CAEmitterLayer()
    private(set) var season: Season?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // never takes a touch
        clipsToBounds = true
        layer.addSublayer(emitter)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        configureGeometry()
    }

    func show(_ s: Season?) {
        guard s != season else { return }
        season = s
        emitter.emitterCells = nil
        guard let s = s else { isHidden = true; return }
        isHidden = false
        emitter.emitterCells = cells(for: s.id)
        emitter.beginTime = CACurrentMediaTime()
        configureGeometry()
    }

    private var rising: Bool { ["vesak", "deepavali", "newyear"].contains(season?.id ?? "") }

    private func configureGeometry() {
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterPosition = rising ? CGPoint(x: bounds.midX, y: bounds.height + 12) : CGPoint(x: bounds.midX, y: -12)
    }

    private func cell(_ img: UIImage?, birth: Float, speed: CGFloat, scale: CGFloat, spin: CGFloat = 0.5, alpha: Float = 0.9) -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = img?.cgImage
        c.birthRate = birth
        c.lifetime = 14
        c.velocity = speed
        c.velocityRange = speed * 0.35
        c.emissionLongitude = rising ? -.pi / 2 : .pi / 2
        c.emissionRange = .pi / 10
        c.scale = scale
        c.scaleRange = scale * 0.35
        c.spin = 0
        c.spinRange = spin
        c.alphaRange = 0.2
        c.alphaSpeed = -0.03
        c.color = UIColor(white: 1, alpha: CGFloat(alpha)).cgColor
        return c
    }

    private func cells(for id: String) -> [CAEmitterCell] {
        switch id {
        case "christmas":
            return [cell(Art.snowflake(18), birth: 2.2, speed: 22, scale: 0.6, spin: 1.2), cell(Art.dot(6, .white), birth: 3, speed: 18, scale: 0.8)]
        case "newyear":
            return [cell(Art.spark(.systemYellow), birth: 1.2, speed: 45, scale: 0.7, spin: 2), cell(Art.spark(.systemPink), birth: 1, speed: 40, scale: 0.6, spin: 2),
                    cell(Art.spark(.systemTeal), birth: 1, speed: 42, scale: 0.6, spin: 2)]
        case "avurudu":
            return [cell(Art.kokis(30), birth: 0.7, speed: 24, scale: 0.75, spin: 0.8), cell(Art.kavum(28), birth: 0.6, speed: 22, scale: 0.75, spin: 0.6),
                    cell(Art.athirasa(28), birth: 0.5, speed: 20, scale: 0.75, spin: 0.6), cell(Art.emoji("🌺", 26), birth: 0.3, speed: 20, scale: 0.6)]
        case "vesak":
            return [cell(Art.lantern(30, .systemYellow), birth: 0.5, speed: 14, scale: 0.75, spin: 0.15), cell(Art.lantern(30, .systemPink), birth: 0.4, speed: 12, scale: 0.7, spin: 0.15),
                    cell(Art.lantern(30, .systemTeal), birth: 0.35, speed: 13, scale: 0.65, spin: 0.15), cell(Art.dot(4, UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)), birth: 1.5, speed: 10, scale: 0.8)]
        case "poson":
            return [cell(Art.emoji("🪷", 26), birth: 0.7, speed: 18, scale: 0.7, spin: 0.4)]
        case "deepavali":
            return [cell(Art.emoji("🪔", 26), birth: 0.5, speed: 12, scale: 0.7, spin: 0.1), cell(Art.dot(5, .systemOrange), birth: 2, speed: 16, scale: 0.8)]
        case "eid":
            return [cell(Art.emoji("🌙", 24), birth: 0.3, speed: 16, scale: 0.7, spin: 0.2), cell(Art.emoji("⭐", 18), birth: 0.8, speed: 18, scale: 0.6, spin: 0.6)]
        case "pongal":
            return [cell(Art.emoji("🌾", 24), birth: 0.6, speed: 18, scale: 0.7, spin: 0.5), cell(Art.emoji("☀️", 22), birth: 0.2, speed: 15, scale: 0.6)]
        case "independence":
            return [cell(Art.emoji("🇱🇰", 24), birth: 0.6, speed: 18, scale: 0.7, spin: 0.5)]
        case "valentine":
            return [cell(Art.emoji("❤️", 22), birth: 0.8, speed: 18, scale: 0.6, spin: 0.4)]
        default: return []
        }
    }
}

/// Small drawings for the effects (drawn once, a few KB each).
enum Art {
    static func render(_ s: CGFloat, _ draw: (CGContext) -> Void) -> UIImage {
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: f).image { draw($0.cgContext) }
    }
    static func emoji(_ e: String, _ s: CGFloat) -> UIImage {
        render(s) { _ in (e as NSString).draw(at: CGPoint(x: 0, y: 0), withAttributes: [.font: UIFont.systemFont(ofSize: s * 0.82)]) }
    }
    static func dot(_ s: CGFloat, _ c: UIColor) -> UIImage {
        render(s) { g in g.setFillColor(c.cgColor); g.fillEllipse(in: CGRect(x: 0, y: 0, width: s, height: s)) }
    }
    static func snowflake(_ s: CGFloat) -> UIImage {
        render(s) { g in
            g.setStrokeColor(UIColor.white.cgColor); g.setLineWidth(1.4); g.setLineCap(.round)
            let c = CGPoint(x: s / 2, y: s / 2), r = s / 2 - 1
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                let e = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                g.move(to: c); g.addLine(to: e)
                for side in [-1.0, 1.0] {
                    let m = CGPoint(x: c.x + cos(a) * r * 0.6, y: c.y + sin(a) * r * 0.6)
                    let b = a + CGFloat(side) * .pi / 4
                    g.move(to: m); g.addLine(to: CGPoint(x: m.x + cos(b) * r * 0.3, y: m.y + sin(b) * r * 0.3))
                }
            }
            g.strokePath()
        }
    }
    static func spark(_ c: UIColor) -> UIImage {
        render(14) { g in
            g.setFillColor(c.cgColor)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 7, y: 0)); p.addLine(to: CGPoint(x: 8.5, y: 5.5)); p.addLine(to: CGPoint(x: 14, y: 7))
            p.addLine(to: CGPoint(x: 8.5, y: 8.5)); p.addLine(to: CGPoint(x: 7, y: 14)); p.addLine(to: CGPoint(x: 5.5, y: 8.5))
            p.addLine(to: CGPoint(x: 0, y: 7)); p.addLine(to: CGPoint(x: 5.5, y: 5.5)); p.close()
            g.addPath(p.cgPath); g.fillPath()
        }
    }
    /// කොකිස් — a golden rosette with holes
    static func kokis(_ s: CGFloat) -> UIImage {
        render(s) { g in
            let gold = UIColor(red: 0.93, green: 0.72, blue: 0.36, alpha: 1), edge = UIColor(red: 0.72, green: 0.47, blue: 0.18, alpha: 1)
            let c = CGPoint(x: s / 2, y: s / 2), r = s * 0.2
            g.setFillColor(gold.cgColor); g.setStrokeColor(edge.cgColor); g.setLineWidth(1)
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                let pc = CGPoint(x: c.x + cos(a) * r * 1.25, y: c.y + sin(a) * r * 1.25)
                let rect = CGRect(x: pc.x - r, y: pc.y - r, width: r * 2, height: r * 2)
                g.fillEllipse(in: rect); g.strokeEllipse(in: rect)
            }
            g.setBlendMode(.clear)
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                let pc = CGPoint(x: c.x + cos(a) * r * 1.3, y: c.y + sin(a) * r * 1.3)
                g.fillEllipse(in: CGRect(x: pc.x - r * 0.42, y: pc.y - r * 0.42, width: r * 0.84, height: r * 0.84))
            }
            g.fillEllipse(in: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.5, width: r, height: r))
        }
    }
    /// කැවුම් — dark brown with the little knob (කොණ්ඩය) on top
    static func kavum(_ s: CGFloat) -> UIImage {
        render(s) { g in
            let brown = UIColor(red: 0.45, green: 0.24, blue: 0.1, alpha: 1), light = UIColor(red: 0.6, green: 0.35, blue: 0.15, alpha: 1)
            g.setFillColor(brown.cgColor)
            g.fillEllipse(in: CGRect(x: s * 0.08, y: s * 0.3, width: s * 0.84, height: s * 0.6))
            g.setFillColor(light.cgColor)
            g.fillEllipse(in: CGRect(x: s * 0.2, y: s * 0.38, width: s * 0.4, height: s * 0.18))
            g.setFillColor(brown.cgColor)
            g.fillEllipse(in: CGRect(x: s * 0.4, y: s * 0.14, width: s * 0.2, height: s * 0.24))
        }
    }
    /// අතිරස — a flat round sweet with a darker ring
    static func athirasa(_ s: CGFloat) -> UIImage {
        render(s) { g in
            g.setFillColor(UIColor(red: 0.55, green: 0.3, blue: 0.12, alpha: 1).cgColor)
            g.fillEllipse(in: CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88))
            g.setFillColor(UIColor(red: 0.72, green: 0.45, blue: 0.2, alpha: 1).cgColor)
            g.fillEllipse(in: CGRect(x: s * 0.2, y: s * 0.2, width: s * 0.6, height: s * 0.6))
            g.setFillColor(UIColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 0.8).cgColor)
            for (x, y) in [(0.35, 0.4), (0.55, 0.32), (0.6, 0.58), (0.4, 0.62)] { g.fillEllipse(in: CGRect(x: s * x, y: s * y, width: s * 0.05, height: s * 0.05)) }
        }
    }
    /// වෙසක් කූඩුව — an eight-sided lantern with paper tails
    static func lantern(_ s: CGFloat, _ c: UIColor) -> UIImage {
        render(s) { g in
            let w = s * 0.62, x0 = (s - w) / 2, y0 = s * 0.06, h = s * 0.55
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x0 + w * 0.3, y: y0)); p.addLine(to: CGPoint(x: x0 + w * 0.7, y: y0))
            p.addLine(to: CGPoint(x: x0 + w, y: y0 + h * 0.35)); p.addLine(to: CGPoint(x: x0 + w, y: y0 + h * 0.65))
            p.addLine(to: CGPoint(x: x0 + w * 0.7, y: y0 + h)); p.addLine(to: CGPoint(x: x0 + w * 0.3, y: y0 + h))
            p.addLine(to: CGPoint(x: x0, y: y0 + h * 0.65)); p.addLine(to: CGPoint(x: x0, y: y0 + h * 0.35)); p.close()
            g.setFillColor(c.withAlphaComponent(0.85).cgColor); g.addPath(p.cgPath); g.fillPath()
            g.setFillColor(UIColor(white: 1, alpha: 0.7).cgColor)
            g.fillEllipse(in: CGRect(x: s / 2 - s * 0.1, y: y0 + h / 2 - s * 0.1, width: s * 0.2, height: s * 0.2))
            g.setStrokeColor(c.cgColor); g.setLineWidth(1.2)
            for i in 0..<4 {
                let x = x0 + w * (0.3 + 0.13 * CGFloat(i))
                g.move(to: CGPoint(x: x, y: y0 + h)); g.addLine(to: CGPoint(x: x + (i % 2 == 0 ? -2 : 2), y: s * 0.98))
            }
            g.strokePath()
        }
    }
}
