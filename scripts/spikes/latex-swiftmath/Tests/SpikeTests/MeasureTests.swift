//
//  MeasureTests.swift
//  LaTeXSpike
//
//  Renders formulas, times them and checks the baseline. Results print as
//  `SPIKE|…` lines; read them with `grep SPIKE`. Not assertions about speed
//  (the simulator is the Mac's CPU); the assertions are about correctness.

#if canImport(UIKit)
import Testing
import UIKit
@testable import Spike

let out: URL = {
    let path = ProcessInfo.processInfo.environment["SPIKE_OUT"] ?? NSTemporaryDirectory()
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}()

func say(_ text: String) { print("SPIKE|\(text)") }

func ms(_ block: () -> Void) -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    block()
    return (CFAbsoluteTimeGetCurrent() - start) * 1000
}

let formulas: [(String, String)] = [
    ("sum of squares", #"x^2 + y^2 = z^2"#),
    ("fraction", #"\frac{n(n+1)}{2}"#),
    ("Big-O", #"O(n \log n)"#),
    ("master theorem", #"T(n) = 2T(n/2) + \Theta(n)"#),
    ("Theta / Omega", #"\Theta(n^2),\ \Omega(\log n)"#),
    ("summation", #"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#),
    ("double sum", #"\sum_{i=1}^{n} \sum_{j=1}^{i} 1"#),
    ("product", #"\prod_{k=1}^{n} k = n!"#),
    ("matrix", #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#),
    ("subscripts", #"F_n = F_{n-1} + F_{n-2},\ a_{i,j}"#),
    ("quadratic", #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#),
    ("integral", #"\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}"#),
    ("ceiling log", #"\lceil \log_2 n \rceil"#),
    ("binomial", #"\binom{n}{k} = \frac{n!}{k!\,(n-k)!}"#),
    ("limit", #"\lim_{n\to\infty} \frac{\log n}{n} = 0"#),
    ("quantifiers", #"\forall x \in \mathbb{R}\ \exists y : y > x"#),
]

@Suite("SwiftMath spike", .serialized) @MainActor
struct MeasureTests {

    static func light() -> UIColor { UIColor.black }
    static func dark() -> UIColor { UIColor.white }

    @Test func render() throws {
        let sizes: [CGFloat] = [14, 17, 24, 36]
        var rows: [(String, UIImage)] = []
        say("formula|size|typeset_ms|image_ms_2x|w|asc|desc|bytes_2x")
        for (name, latex) in formulas {
            for size in sizes {
                var made: Formula?
                let t1 = ms {
                    if case .drawn(let f) = Formula.make(latex: latex, fontSize: size, display: size >= 24) { made = f }
                }
                let f = try #require(made, "\(name) failed to parse")
                var image: UIImage?
                let t2 = ms { image = f.image(color: Self.light(), scale: 2) }
                let img = try #require(image)
                let bytes = Int(img.size.width * 2 * img.size.height * 2 * 4)
                say(String(format: "%@|%.0f|%.2f|%.2f|%.1f|%.1f|%.1f|%d", name, size, t1, t2, f.metrics.width, f.metrics.ascent, f.metrics.descent, bytes))
                if size == 17 || size == 36 { rows.append(("\(name) @\(Int(size))", img)) }
            }
        }
        try contactSheet(rows, dark: false, name: "sheet-light.png")
        try contactSheet(rows, dark: true, name: "sheet-dark.png")
    }

    func contactSheet(_ rows: [(String, UIImage)], dark: Bool, name: String) throws {
        let width: CGFloat = 900
        let heights = rows.map { max($0.1.size.height, 20) + 8 }
        let total = heights.reduce(0, +) + 8
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: width, height: total), format: format).image { ctx in
            (dark ? UIColor.black : UIColor.white).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: total))
            var y: CGFloat = 8
            for (i, row) in rows.enumerated() {
                let label = row.0 as NSString
                label.draw(at: CGPoint(x: 8, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: dark ? UIColor.gray : UIColor.darkGray])
                // tinted copy: the rows were drawn black; invert for dark
                let image = dark ? row.1.withTintColor(.white, renderingMode: .alwaysTemplate) : row.1
                image.draw(at: CGPoint(x: 220, y: y))
                y += heights[i]
            }
        }
        try sheet.pngData()!.write(to: out.appendingPathComponent(name))
    }

    /// What colour does the image carry? Render in both and compare.
    @Test func lightAndDark() throws {
        guard case .drawn(let f) = Formula.make(latex: #"\frac{a}{b}"#, fontSize: 17, display: false) else { Issue.record("parse"); return }
        func inkColours(_ image: UIImage) -> Set<UInt32> {
            let cg = image.cgImage!
            let w = cg.width, h = cg.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            var set = Set<UInt32>()
            for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 250 {
                set.insert(UInt32(data[i]) << 16 | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]))
            }
            return set
        }
        let black = inkColours(f.image(color: .black, scale: 2))
        let white = inkColours(f.image(color: .white, scale: 2))
        let orange = inkColours(f.image(color: UIColor(red: 0.9, green: 0.28, blue: 0.3, alpha: 1), scale: 2))
        say("opaque ink colours: black=\(black.map { String($0, radix: 16) }) white=\(white.map { String($0, radix: 16) }) red=\(orange.map { String($0, radix: 16) })")
        #expect(white.contains(0xFFFFFF))
        #expect(black.contains(0x000000))
        // a dynamic colour must be resolved by the caller: the label takes its cgColor at draw time
        let dynamic = UIColor { $0.userInterfaceStyle == .dark ? .white : .black }
        let resolvedDark = dynamic.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(inkColours(f.image(color: resolvedDark, scale: 2)).contains(0xFFFFFF))
    }

    /// "H" then a descender: the H's bottom must sit `descent` above the
    /// image's bottom edge (the baseline the metrics promise), and the image
    /// must be the right way up (the descender is in the lower rows).
    @Test func baselineIsWhereTheMetricsSay() throws {
        for size: CGFloat in [14, 17, 24, 36] {
            guard case .drawn(let f) = Formula.make(latex: #"H\,\,p"#, fontSize: size, display: false) else { Issue.record("parse"); return }
            let scale: CGFloat = 4
            let cg = f.image(color: .black, scale: scale).cgImage!
            let w = cg.width, h = cg.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            func rows(columns: Range<Int>) -> (top: Int, bottom: Int) {
                var top = h, bottom = -1
                for row in 0..<h { for col in columns where data[(row * w + col) * 4 + 3] > 128 { top = min(top, row); bottom = max(bottom, row) } }
                return (top, bottom + 1)
            }
            let hInk = rows(columns: 0..<Int(f.metrics.width * scale * 0.3))
            let pInk = rows(columns: Int(f.metrics.width * scale * 0.7)..<w)
            let expected = (f.metrics.height - f.metrics.descent) * scale
            say(String(format: "baseline @%.0f: H bottom row %d, expected %.1f; H top %d; p bottom %d of %d (descender reaches %.2fpt below baseline, metrics descent %.2f)", size, hInk.bottom, expected, hInk.top, pInk.bottom, h, (CGFloat(pInk.bottom) - expected) / scale, f.metrics.descent))
            #expect(abs(CGFloat(hInk.bottom) - expected) <= 2, "H at \(size)")
            #expect(pInk.bottom > hInk.bottom + 2, "descender must hang below the H: image right way up")
        }
    }

    /// Does the system font's cap height match Latin Modern's at the same size?
    @Test func fontMatching() {
        for size: CGFloat in [14, 17, 24] {
            let body = UIFont.preferredFont(forTextStyle: .body).withSize(size)
            guard case .drawn(let f) = Formula.make(latex: "x", fontSize: size, display: false) else { return }
            say(String(format: "size %.0f: SF xHeight %.2f capHeight %.2f | formula 'x' ascent %.2f descent %.2f", size, body.xHeight, body.capHeight, f.metrics.ascent, f.metrics.descent))
        }
    }

    @Test func errorsAndUnsupported() {
        let probes: [(String, String)] = [
            ("unbalanced brace", #"\frac{a}{"#), ("unknown command", #"\foo{x}"#), ("empty", ""),
            ("mathbb", #"\mathbb{R}"#), ("mathcal", #"\mathcal{O}(1)"#), ("mathbf", #"\mathbf{v}"#),
            ("text", #"\text{if } n > 0"#), ("operatorname", #"\operatorname{lcm}(a,b)"#),
            ("cases", #"f(n)=\begin{cases} 1 & n=0 \\ n f(n-1) & n>0 \end{cases}"#),
            ("aligned", #"\begin{aligned} a &= b \\ c &= d \end{aligned}"#),
            ("align*", #"\begin{align*} a &= b \end{align*}"#),
            ("array", #"\begin{array}{cc} 1 & 2 \\ 3 & 4 \end{array}"#),
            ("bmatrix", #"\begin{bmatrix} 1 & 0 \\ 0 & 1 \end{bmatrix}"#),
            ("underbrace", #"\underbrace{a+b}_{n}"#), ("overbrace", #"\overbrace{a+b}^{n}"#),
            ("overline", #"\overline{AB}"#), ("xrightarrow", #"A \xrightarrow{f} B"#),
            ("cancel", #"\cancel{x}"#), ("boxed", #"\boxed{x}"#), ("dfrac", #"\dfrac{a}{b}"#),
            ("bmod", #"a \bmod n"#), ("pmod", #"a \equiv b \pmod{n}"#), ("substack", #"\sum_{\substack{i<n\\j<i}} 1"#),
            ("overset", #"\overset{!}{=}"#), ("color", #"{\color{red} x}"#), ("tag", #"x = 1 \tag{1}"#),
            ("newcommand", #"\newcommand{\R}{\mathbb{R}} \R"#), ("ldots/vdots", #"a_1, \ldots, a_n \quad \vdots"#),
            ("arrows", #"f: A \mapsto B \Rightarrow C \iff D \implies E"#), ("relations", #"a \leq b \neq c \approx d \equiv e"#),
            ("sets", #"A \cup B \cap C \setminus \emptyset \subseteq \varnothing"#), ("logic", #"p \land q \lor \lnot r \oplus s"#),
            ("floor", #"\lfloor x \rfloor"#), ("bigcup", #"\bigcup_{i} A_i"#), ("limits", #"\max\limits_{i} a_i"#),
            ("argmin", #"\arg\min_{x} f(x)"#), ("operatorname*", #"\operatorname*{argmax}_x f"#),
            ("text in sub", #"x_{\text{max}}"#), ("sqrt n", #"\sqrt[3]{x}"#), ("hat/vec", #"\hat{x}\ \vec{v}\ \bar{y}"#),
            ("not", #"a \not\equiv b"#), ("left-right", #"\left( \frac{a}{b} \right)"#), ("tilde", #"\tilde{x}"#),
            ("mathrm", #"\mathrm{d}x"#), ("mathsf", #"\mathsf{P}"#), ("mathtt", #"\mathtt{x}"#),
            ("dots", #"1 + 2 + \cdots + n"#), ("align \\\\ outside env", #"a \\ b"#), ("sideset", #"\sideset{_a}{_b}\sum"#),
            ("href", #"\href{x}{y}"#), ("hline array", #"\begin{array}{|c|c|} \hline 1 & 2 \\ \hline \end{array}"#),
            ("textbf", #"\textbf{x}"#), ("displaystyle", #"\displaystyle\sum_i x_i"#), ("choose", #"{n \choose k}"#),
        ]
        say("probe|result")
        for (name, latex) in probes {
            switch Formula.make(latex: latex, fontSize: 17, display: false) {
            case .drawn(let f): say("\(name)|OK w=\(String(format: "%.1f", f.metrics.width)) h=\(String(format: "%.1f", f.metrics.height))")
            case .failed(let message): say("\(name)|FAIL \(message)")
            }
        }
    }

    /// Caching: how long a formula's second use takes, and what `render` costs in bulk.
    @Test func bulk() throws {
        let latex = #"\sum_{i=1}^{n} \frac{i}{i+1}"#
        var total = 0.0
        let n = 200
        total = ms { for _ in 0..<n { _ = Formula.make(latex: latex, fontSize: 17, display: false) } }
        say(String(format: "typeset ×%d: %.2f ms each", n, total / Double(n)))
        guard case .drawn(let f) = Formula.make(latex: latex, fontSize: 17, display: false) else { return }
        let t = ms { for _ in 0..<n { _ = f.image(color: .black, scale: 2) } }
        say(String(format: "image ×%d at 2x: %.2f ms each", n, t / Double(n)))
        let t3 = ms { for _ in 0..<n { _ = f.image(color: .black, scale: 3) } }
        say(String(format: "image ×%d at 3x: %.2f ms each", n, t3 / Double(n)))
        // vector into a PDF
        let pdf = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdf, CGRect(x: 0, y: 0, width: 300, height: 100), nil)
        UIGraphicsBeginPDFPage()
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.translateBy(x: 0, y: 100); ctx.scaleBy(x: 1, y: -1)   // y up like SwiftMath
        f.draw(in: ctx, baselineOrigin: CGPoint(x: 20, y: 50), color: .black)
        UIGraphicsEndPDFContext()
        try pdf.write(to: out.appendingPathComponent("vector.pdf"))
        say("vector PDF bytes: \(pdf.length)")
    }
}
#endif
