import Foundation
import SwiftUI

/// The loading animation of the iPhone app, the same as the web app's (index.html, #ana-splash): the bone grows in,
/// the heart pops out of one end and beats with the ECG line under the "Anatomia." wordmark, the star shoots out of the
/// other end and twinkles, Latin names drift in the background. The app draws it itself instead of the web view: the
/// web view can only draw between the page's big scripts, so its animation would stand still while the page loads.
/// AnatomiaApp lays it over the web view until the page reports that the app is on screen (SplashModel).
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                SplashScene.draw(in: &context, size: size, t: timeline.date.timeIntervalSince(start), still: reduceMotion)
            }
        }
        .background(SplashScene.navy)
        .accessibilityHidden(true)
    }
}

/// Whether the loading animation is shown: from the start until the page reports (message "splash", SplashBridge) that
/// the app is on screen, at least 1.6 s so that the animation can be seen, at the latest after 20 s.
final class SplashModel: ObservableObject {
    @Published private(set) var visible = true
    private var shownAt = Date()
    private var fallback: DispatchWorkItem?

    init() {
        armFallback()
    }

    /// the app is on screen: the animation fades out (once it has been shown long enough)
    func done() {
        guard visible else { return }
        let wait = max(0, 1.6 - Date().timeIntervalSince(shownAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self = self, self.visible else { return }
            self.fallback?.cancel()
            withAnimation(.easeOut(duration: 0.45)) {
                self.visible = false
            }
        }
    }

    /// the page loads again (iOS ended its process): the animation is shown again meanwhile
    func show() {
        shownAt = Date()
        visible = true
        armFallback()
    }

    private func armFallback() {
        fallback?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.done()
        }
        fallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }
}

/// The drawing, frame by frame at time t (s) since the start. Times and sizes follow the CSS of the web app's loading
/// screen (in index.html: #ana-splash-css), so both look the same.
enum SplashScene {
    static let navy = Color(red: 30 / 255, green: 40 / 255, blue: 54 / 255)
    static let mint = Color(red: 94 / 255, green: 242 / 255, blue: 195 / 255)
    static let heartRed = Color(red: 239 / 255, green: 72 / 255, blue: 72 / 255)
    static let dotRed = Color(red: 1, green: 90 / 255, blue: 90 / 255)
    static let starGold = Color(red: 247 / 255, green: 190 / 255, blue: 18 / 255)
    static let sparkGold = Color(red: 1, green: 229 / 255, blue: 138 / 255)
    static let termColor = Color(red: 226 / 255, green: 220 / 255, blue: 1, opacity: 0.2)

    static func violet(_ a: Double) -> Color { Color(red: 116 / 255, green: 81 / 255, blue: 232 / 255, opacity: a) }
    static func lilac(_ a: Double) -> Color { Color(red: 160 / 255, green: 130 / 255, blue: 1, opacity: a) }
    static func ink(_ a: Double) -> Color { Color(red: 14 / 255, green: 20 / 255, blue: 32 / 255, opacity: a) }

    // MARK: timing (the CSS easing curves and keyframes)

    /// CSS cubic-bezier(x1, y1, x2, y2) at progress p (0...1)
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ p: Double) -> Double {
        if p <= 0 { return 0 }
        if p >= 1 { return 1 }
        func bx(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s }
        func by(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if bx(mid) < p { lo = mid } else { hi = mid }
        }
        return by((lo + hi) / 2)
    }

    static func easeOut(_ p: Double) -> Double { bezier(0, 0, 0.58, 1, p) }
    static func easeInOut(_ p: Double) -> Double { bezier(0.42, 0, 0.58, 1, p) }
    static func back(_ p: Double) -> Double { bezier(0.34, 1.56, 0.64, 1, p) }

    /// how far an animation that starts after `delay` and lasts `duration` has got (0 before, 1 after)
    static func progress(_ t: Double, _ delay: Double, _ duration: Double) -> Double {
        min(max((t - delay) / duration, 0), 1)
    }

    /// the place (0..<1) in a loop of `period` s that starts after `delay`
    static func phase(_ t: Double, _ delay: Double, _ period: Double) -> Double {
        t <= delay ? 0 : (t - delay).truncatingRemainder(dividingBy: period) / period
    }

    /// the value of keyframes [(place 0...1, value)] at p, each step eased with `ease`
    static func keyframes(_ p: Double, _ k: [(Double, Double)], ease: (Double) -> Double = { $0 }) -> Double {
        guard let first = k.first, let last = k.last else { return 0 }
        if p <= first.0 { return first.1 }
        for i in 1..<k.count where p <= k[i].0 {
            let a = k[i - 1]
            let b = k[i]
            let u = b.0 > a.0 ? (p - a.0) / (b.0 - a.0) : 1
            return a.1 + (b.1 - a.1) * ease(u)
        }
        return last.1
    }

    // MARK: shapes

    /// the bone, centred on (0, 0), lying flat (the drawing turns it by -45°)
    static let bone: [Path] = [
        Path(roundedRect: CGRect(x: -54, y: -9, width: 108, height: 18), cornerRadius: 9),
        Path(ellipseIn: CGRect(x: -65.5, y: -21.5, width: 23, height: 23)),
        Path(ellipseIn: CGRect(x: -65.5, y: -1.5, width: 23, height: 23)),
        Path(ellipseIn: CGRect(x: 42.5, y: -21.5, width: 23, height: 23)),
        Path(ellipseIn: CGRect(x: 42.5, y: -1.5, width: 23, height: 23)),
    ]

    /// the heart in a 40 × 36 box
    static let heart: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 20, y: 34))
        p.addCurve(to: CGPoint(x: 1, y: 10.5), control1: CGPoint(x: 8, y: 25), control2: CGPoint(x: 1, y: 18))
        p.addCurve(to: CGPoint(x: 10.4, y: 1), control1: CGPoint(x: 1, y: 5), control2: CGPoint(x: 5.2, y: 1))
        p.addCurve(to: CGPoint(x: 20, y: 6.6), control1: CGPoint(x: 14.2, y: 1), control2: CGPoint(x: 17.6, y: 3.2))
        p.addCurve(to: CGPoint(x: 29.6, y: 1), control1: CGPoint(x: 22.4, y: 3.2), control2: CGPoint(x: 25.8, y: 1))
        p.addCurve(to: CGPoint(x: 39, y: 10.5), control1: CGPoint(x: 34.8, y: 1), control2: CGPoint(x: 39, y: 5))
        p.addCurve(to: CGPoint(x: 20, y: 34), control1: CGPoint(x: 39, y: 18), control2: CGPoint(x: 32, y: 25))
        p.closeSubpath()
        return p
    }()

    /// the five-pointed star in a 40 × 40 box
    static let star: Path = {
        var p = Path()
        for k in 0..<10 {
            let a = -Double.pi / 2 + Double(k) * Double.pi / 5
            let r = k % 2 == 0 ? 19.5 : 8.2
            let pt = CGPoint(x: 20 + r * cos(a), y: 21 + r * sin(a))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }()

    /// a small four-pointed sparkle in a 12 × 12 box
    static let spark: Path = {
        let pts: [(Double, Double)] = [(6, 0), (7.3, 4.7), (12, 6), (7.3, 7.3), (6, 12), (4.7, 7.3), (0, 6), (4.7, 4.7)]
        var p = Path()
        for (i, q) in pts.enumerated() {
            let pt = CGPoint(x: q.0, y: q.1)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }()

    /// four heartbeats of the ECG: one beat is 100 wide, the line 26 down in a 44 high strip
    static let trace: Path = {
        let beat: [(Double, Double)] = [(0, 26), (14, 26), (16, 23.5), (19, 21.5), (22, 23.5), (24, 26), (30, 26), (33, 29),
                                        (37, 4), (41, 36), (44, 26), (52, 26), (55, 24.2), (58, 20.8), (61, 19.6), (64, 21),
                                        (67, 24.4), (70, 26), (100, 26)]
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 26))
        for k in 0..<4 {
            for q in beat {
                p.addLine(to: CGPoint(x: q.0 + Double(k) * 100, y: q.1))
            }
        }
        return p
    }()

    /// the height of the pen (the bright dot at the end of the ECG line) during one beat: it follows the line
    static let pen: [(Double, Double)] = [(0.04, 0), (0.06, -2.5), (0.09, -4.5), (0.12, -2.5), (0.14, 0), (0.2, 0), (0.23, 3),
                                          (0.27, -22), (0.31, 10), (0.34, 0), (0.42, 0), (0.45, -1.8), (0.48, -5.2),
                                          (0.51, -6.4), (0.54, -5), (0.57, -1.6), (0.6, 0), (0.9, 0), (1, 0)]

    /// the heartbeat (scale), with the R spike of the ECG passing the pen at 27 % of the beat
    static let beat: [(Double, Double)] = [(0, 1), (0.25, 1), (0.31, 1.24), (0.38, 0.95), (0.45, 1.1), (0.55, 1), (1, 1)]

    // MARK: the Latin names in the background

    struct Term {
        let name: String
        let size: Double
        let duration: Double
        let delay: Double
    }

    struct Row {
        let top: Double
        let pad: Double
        let terms: [Term]
    }

    struct Edge {
        let fromLeft: Bool
        let x: Double
        let top: Double
        let term: Term
    }

    static let rows: [Row] = [
        Row(top: 0.036, pad: 0.00, terms: [
            Term(name: "Os femoris", size: 14, duration: 8.6, delay: -0.4),
            Term(name: "Cor", size: 17, duration: 7.4, delay: -4.3),
            Term(name: "Hepar", size: 17, duration: 7.9, delay: -0.7),
            Term(name: "Scapula", size: 16, duration: 7.3, delay: -0.7),
            Term(name: "Clavicula", size: 16, duration: 7.2, delay: -4.1),
        ]),
        Row(top: 0.129, pad: 0.06, terms: [
            Term(name: "Humerus", size: 18, duration: 9.5, delay: -9.0),
            Term(name: "Pulmo", size: 17, duration: 9.3, delay: -0.5),
            Term(name: "Radius", size: 14, duration: 7.2, delay: -6.2),
            Term(name: "Ulna", size: 15, duration: 8.7, delay: -4.7),
            Term(name: "Sternum", size: 17, duration: 8.2, delay: -6.7),
        ]),
        Row(top: 0.194, pad: 0.12, terms: [
            Term(name: "Tibia", size: 17, duration: 9.3, delay: -1.7),
            Term(name: "Patella", size: 13, duration: 9.2, delay: -0.6),
            Term(name: "Cranium", size: 13, duration: 9.5, delay: -4.7),
            Term(name: "Aorta", size: 17, duration: 8.7, delay: -2.7),
            Term(name: "Atlas", size: 17, duration: 10.7, delay: -3.9),
        ]),
        Row(top: 0.775, pad: 0.00, terms: [
            Term(name: "Mandibula", size: 14, duration: 9.8, delay: -2.4),
            Term(name: "Vena cava", size: 17, duration: 8.2, delay: -4.1),
            Term(name: "Nervus vagus", size: 15, duration: 9.9, delay: -2.9),
            Term(name: "Cerebrum", size: 13, duration: 7.5, delay: -3.1),
            Term(name: "Talus", size: 15, duration: 7.6, delay: -3.7),
        ]),
        Row(top: 0.851, pad: 0.06, terms: [
            Term(name: "Fibula", size: 18, duration: 7.3, delay: -4.1),
            Term(name: "Diaphragma", size: 15, duration: 8.4, delay: -2.9),
            Term(name: "Pancreas", size: 16, duration: 9.3, delay: -4.3),
            Term(name: "Ren", size: 13, duration: 10.8, delay: -5.1),
            Term(name: "Axis", size: 18, duration: 7.3, delay: -5.3),
        ]),
        Row(top: 0.936, pad: 0.12, terms: [
            Term(name: "M. deltoideus", size: 17, duration: 11.0, delay: -9.0),
            Term(name: "Calcaneus", size: 15, duration: 9.9, delay: -8.8),
            Term(name: "Vertebrae", size: 15, duration: 7.1, delay: -3.3),
            Term(name: "Lien", size: 14, duration: 9.4, delay: -4.7),
            Term(name: "Gaster", size: 14, duration: 10.1, delay: -1.3),
        ]),
    ]

    static let edges: [Edge] = [
        Edge(fromLeft: true, x: -0.05, top: 0.34, term: Term(name: "Costae", size: 14, duration: 8.6, delay: -7.9)),
        Edge(fromLeft: false, x: -0.04, top: 0.40, term: Term(name: "Pelvis", size: 16, duration: 7.3, delay: -3.3)),
        Edge(fromLeft: true, x: -0.06, top: 0.50, term: Term(name: "Ilium", size: 17, duration: 8.1, delay: -1.1)),
        Edge(fromLeft: false, x: -0.05, top: 0.56, term: Term(name: "Sacrum", size: 16, duration: 10.5, delay: -2.9)),
        Edge(fromLeft: true, x: -0.04, top: 0.66, term: Term(name: "Carpus", size: 16, duration: 10.9, delay: -7.5)),
        Edge(fromLeft: false, x: -0.06, top: 0.72, term: Term(name: "Tarsus", size: 16, duration: 10.8, delay: -1.6)),
    ]

    /// the line under the animation in the phone's language (the web app starts in it too)
    static let loadingText: String = {
        switch String((Locale.preferredLanguages.first ?? "en").prefix(2)) {
        case "de": return "Wird geladen …"
        case "es": return "Cargando …"
        case "sv": return "Laddar …"
        case "nb", "no", "nn": return "Laster inn …"
        default: return "Loading …"
        }
    }()

    // MARK: drawing

    static func draw(in ctx: inout GraphicsContext, size: CGSize, t rawT: Double, still: Bool) {
        let w = Double(size.width)
        let h = Double(size.height)
        // with reduced motion: the finished picture, standing still
        let t = still ? 5.0 : rawT
        let lt = still ? 0.6 : rawT
        let whole = Path(CGRect(origin: .zero, size: size))

        // the ground, the violet light from the top left (as in the icon) and the darker corner
        ctx.fill(whole, with: .color(navy))
        var aura = ctx
        aura.opacity = easeOut(progress(t, 0.05, 1.1))
        aura.fill(whole, with: .radialGradient(
            Gradient(stops: [.init(color: violet(0.9), location: 0), .init(color: violet(0.38), location: 0.4),
                             .init(color: violet(0), location: 0.72)]),
            center: CGPoint(x: 0.12 * w, y: 0), startRadius: 0, endRadius: (1.3 * w + 0.7 * h) / 2))
        aura.fill(whole, with: .radialGradient(
            Gradient(stops: [.init(color: ink(0.85), location: 0), .init(color: ink(0), location: 0.7)]),
            center: CGPoint(x: w, y: h), startRadius: 0, endRadius: (0.9 * w + 0.5 * h) / 2))

        if !still {
            drawTerms(&ctx, w: w, h: h, t: t)
        }

        // the block in the middle: logo 176, wordmark, ECG, loading line (326 high, a little above the centre)
        let top: Double = (h - 326) / 2 - 0.02 * h
        let lx: Double = w / 2 - 88
        let float: Double = t < 1.4 || still ? 0 : keyframes(phase(t, 1.4, 3.2), [(0, 0), (0.5, -5), (1, 0)], ease: easeInOut)
        let ly: Double = top + float
        let beatPlace = phase(lt, 0.6, 1.0)
        let beating = lt > 0.6

        // the glow behind the logo, pulsing with the heart
        let glowIn = easeOut(progress(t, 0.1, 1.1))
        if glowIn > 0 {
            let pulse = beating ? keyframes(beatPlace, [(0, 1), (0.25, 1), (0.32, 1.12), (0.7, 1), (1, 1)], ease: easeOut) : 1
            let bright = beating ? keyframes(beatPlace, [(0, 0.85), (0.25, 0.85), (0.32, 1), (0.7, 0.85), (1, 0.85)], ease: easeOut) : 0.85
            let r: Double = 160 * (0.55 + 0.45 * glowIn) * pulse
            let gx: Double = lx + 88
            let gy: Double = ly + 88
            var g = ctx
            g.opacity = glowIn * bright
            g.fill(Path(ellipseIn: CGRect(x: gx - r, y: gy - r, width: 2 * r, height: 2 * r)), with: .radialGradient(
                Gradient(stops: [.init(color: lilac(0.5), location: 0), .init(color: lilac(0.16), location: 0.42),
                                 .init(color: lilac(0), location: 0.7)]),
                center: CGPoint(x: gx, y: gy), startRadius: 0, endRadius: r))
        }

        // the bone grows from its middle (turned by -45°, with a soft shadow)
        let boneP = progress(t, 0.12, 0.8)
        if boneP > 0 {
            let e = bezier(0.3, 1.45, 0.5, 1, boneP)
            var b = ctx
            b.opacity = min(1, boneP / 0.35)
            b.translateBy(x: lx + 88, y: ly + 88)
            b.rotate(by: .degrees(-45))
            b.scaleBy(x: max(0.001, 0.08 + 0.92 * e), y: max(0.001, 0.5 + 0.5 * e))
            var shadow = b
            shadow.opacity = b.opacity * 0.28
            shadow.drawLayer { layer in
                layer.translateBy(x: 0, y: 3)
                for part in bone {
                    layer.fill(part, with: .color(Color(red: 20 / 255, green: 10 / 255, blue: 60 / 255)))
                }
            }
            for part in bone {
                b.fill(part, with: .color(.white))
            }
        }

        // the heart pops out of the lower end and beats, with rings at each beat
        let heartP = progress(t, 0.45, 0.6)
        if heartP > 0 {
            let e = max(0.001, back(heartP))
            var hc = ctx
            hc.opacity = min(1, heartP / 0.35)
            hc.translateBy(x: lx + 31 + 14 * (1 - e), y: ly + 147 - 14 * (1 - e))
            hc.scaleBy(x: e, y: e)
            for (delay, color) in [(0.6, Color(red: 1, green: 98 / 255, blue: 98 / 255, opacity: 0.8)),
                                   (0.74, Color(red: 1, green: 150 / 255, blue: 150 / 255, opacity: 0.55))] where lt > delay {
                let p = phase(lt, delay, 1.0)
                let s = keyframes(p, [(0, 0.5), (0.25, 0.5), (0.78, 2.7), (1, 2.7)], ease: easeOut)
                let a = keyframes(p, [(0, 0), (0.25, 0), (0.28, 0.95), (0.78, 0), (1, 0)], ease: easeOut)
                if a > 0.001 {
                    var ring = hc
                    ring.opacity *= a
                    let r = 19 * s
                    ring.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(color), lineWidth: 2 * s)
                }
            }
            let s = beating ? keyframes(beatPlace, beat, ease: easeInOut) : 1
            hc.translateBy(x: 0, y: 1.8)
            hc.scaleBy(x: s, y: s)
            hc.translateBy(x: -20, y: -19.8)
            hc.fill(heart, with: .color(heartRed))
            var shine = hc
            shine.opacity *= 0.35
            shine.translateBy(x: 11, y: 9)
            shine.rotate(by: .degrees(-30))
            shine.fill(Path(ellipseIn: CGRect(x: -4.2, y: -2.8, width: 8.4, height: 5.6)), with: .color(.white))
        }

        // the star shoots out of the upper end, then twinkles, with sparkles around it
        let starP = progress(t, 0.6, 0.75)
        if starP > 0 {
            let e = max(0.001, back(starP))
            var sc = ctx
            sc.opacity = min(1, starP / 0.3)
            sc.translateBy(x: lx + 147 - 30 * (1 - e), y: ly + 29 + 30 * (1 - e))
            sc.rotate(by: .degrees(-160 * (1 - e)))
            sc.scaleBy(x: e, y: e)
            for (x, y, delay) in [(-12.0, 2.0, 1.5), (40.0, 10.0, 2.1), (14.0, 40.0, 2.7)] where lt > delay {
                let p = phase(lt, delay, 2.4)
                let a = keyframes(p, [(0, 0), (0.45, 1), (0.7, 0), (1, 0)], ease: easeInOut)
                let k = keyframes(p, [(0, 0), (0.45, 1), (0.7, 0.2), (1, 0)], ease: easeInOut)
                let turn = keyframes(p, [(0, 0), (0.45, 90), (0.7, 140), (1, 0)], ease: easeInOut)
                if a > 0.001 && k > 0.001 {
                    var sp = sc
                    sp.opacity *= a
                    sp.translateBy(x: x - 16, y: y - 16)
                    sp.rotate(by: .degrees(turn))
                    sp.scaleBy(x: k, y: k)
                    sp.translateBy(x: -6, y: -6)
                    sp.fill(spark, with: .color(sparkGold))
                }
            }
            let tw = lt > 1.4 ? keyframes(phase(lt, 1.4, 2.4), [(0, 0), (0.5, 1), (1, 0)], ease: easeInOut) : 0
            sc.rotate(by: .degrees(16 * tw))
            sc.scaleBy(x: 1 + 0.12 * tw, y: 1 + 0.12 * tw)
            sc.translateBy(x: -20, y: -20)
            sc.fill(star, with: .color(starGold))
        }

        // the wordmark: the letters rise one after another, then the red dot pops in and beats with the heart
        let wordY: Double = top + 176 + 14 + 23
        let font = Font.system(size: 42, weight: .bold, design: .rounded)
        let big = CGSize(width: 400, height: 100)
        let letters = "Anatomia".map { ctx.resolve(Text(String($0)).font(font).foregroundColor(.white)) }
        let dot = ctx.resolve(Text(".").font(font).foregroundColor(dotRed))
        let widths: [Double] = letters.map { Double($0.measure(in: big).width) }
        let dotWidth = Double(dot.measure(in: big).width)
        let total: Double = widths.reduce(0, +) + dotWidth + Double(letters.count) * 0.5
        var x: Double = w / 2 - total / 2
        var word = ctx
        word.addFilter(.shadow(color: Color(red: 8 / 255, green: 6 / 255, blue: 30 / 255, opacity: 0.35), radius: 7, x: 0, y: 3))
        for (i, letter) in letters.enumerated() {
            let p = progress(t, 0.5 + 0.05 * Double(i), 0.65)
            if p > 0 {
                let e = bezier(0.2, 0.9, 0.3, 1.25, p)
                var l = word
                l.opacity = min(1, e)
                l.translateBy(x: x + widths[i] / 2, y: wordY + 18 * (1 - e))
                l.scaleBy(x: 0.9 + 0.1 * e, y: 0.9 + 0.1 * e)
                l.draw(letter, at: .zero, anchor: .center)
            }
            x += widths[i] + 0.5
        }
        let dotP = progress(t, 1.05, 0.5)
        if dotP > 0 {
            let e = max(0.001, back(dotP))
            let k = beating ? keyframes(beatPlace, [(0, 1), (0.25, 1), (0.31, 1.45), (0.38, 1), (1, 1)], ease: easeInOut) : 1
            var d = word
            d.opacity = min(1, dotP / 0.35)
            d.translateBy(x: x + dotWidth / 2 + 14 * (1 - e), y: wordY - 14 * (1 - e))
            d.scaleBy(x: e, y: e)
            d.translateBy(x: 0, y: 12)
            d.scaleBy(x: k, y: k)
            d.translateBy(x: 0, y: -12)
            d.draw(dot, at: .zero, anchor: .center)
        }

        // the ECG: the line scrolls past the pen, one beat per second, fading out to the left
        let ecgY: Double = top + 176 + 14 + 46 + 12
        let ex: Double = w / 2 - 112
        let ecgIn = easeOut(progress(t, 0.55, 0.6))
        if ecgIn > 0 {
            let shift = beating ? 100 * beatPlace : 0
            let window = CGRect(x: ex, y: ecgY, width: 210, height: 44)
            var ecg = ctx
            ecg.opacity = ecgIn
            ecg.drawLayer { layer in
                layer.clip(to: Path(window))
                let line = trace.offsetBy(dx: ex - shift, dy: ecgY)
                layer.stroke(line, with: .color(mint.opacity(0.22)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                layer.stroke(line, with: .color(mint), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                layer.blendMode = .destinationIn
                layer.fill(Path(window), with: .linearGradient(Gradient(colors: [.clear, .black]),
                                                               startPoint: CGPoint(x: ex, y: 0), endPoint: CGPoint(x: ex + 115.5, y: 0)))
            }
            let py = beating ? keyframes(beatPlace, pen) : 0
            var dotPen = ecg
            dotPen.addFilter(.shadow(color: mint.opacity(0.85), radius: 6))
            dotPen.fill(Path(ellipseIn: CGRect(x: ex + 206, y: ecgY + 22 + py, width: 8, height: 8)), with: .color(.white))
        }

        // "Wird geladen …", if it takes longer
        let loadIn = easeOut(progress(t, 2.2, 0.6))
        if loadIn > 0 {
            var l = ctx
            l.opacity = loadIn
            l.draw(Text(loadingText).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(Color.white.opacity(0.62)),
                   at: CGPoint(x: w / 2, y: ecgY + 44 + 16 + 9), anchor: .center)
        }
    }

    /// the Latin names: rows above and below the logo, the names spread out in each row, and some at the edges; each
    /// fades in, drifts up a little and fades out again, in its own rhythm
    static func drawTerms(_ ctx: inout GraphicsContext, w: Double, h: Double, t: Double) {
        var c = ctx
        c.opacity = easeOut(progress(t, 0.3, 1.4))
        guard c.opacity > 0 else { return }
        let big = CGSize(width: 1000, height: 100)
        func one(_ term: Term, x: Double, y: Double, text: GraphicsContext.ResolvedText) {
            let u: Double = (t - term.delay).truncatingRemainder(dividingBy: term.duration) / term.duration
            let a: Double = u < 0.18 ? u / 0.18 : (u > 0.82 ? (1 - u) / 0.18 : 1)
            var tc = c
            tc.opacity *= a
            tc.draw(text, at: CGPoint(x: x, y: y + 11 - 22 * u), anchor: .center)
        }
        func resolved(_ term: Term) -> GraphicsContext.ResolvedText {
            c.resolve(Text(term.name).font(.custom("Georgia-Italic", size: term.size)).foregroundColor(termColor))
        }
        for row in rows {
            let texts = row.terms.map(resolved)
            let widths: [Double] = texts.map { Double($0.measure(in: big).width) }
            let left: Double = -0.12 * w + row.pad * w
            let used: Double = widths.reduce(0, +)
            let gap: Double = (1.12 * w - left - used) / Double(texts.count)
            var x: Double = left + gap / 2
            for (i, text) in texts.enumerated() {
                one(row.terms[i], x: x + widths[i] / 2, y: row.top * h + 10, text: text)
                x += widths[i] + gap
            }
        }
        for edge in edges {
            let text = resolved(edge.term)
            let width = Double(text.measure(in: big).width)
            let cx: Double = edge.fromLeft ? edge.x * w + width / 2 : w - edge.x * w - width / 2
            one(edge.term, x: cx, y: edge.top * h + 10, text: text)
        }
    }
}
