//
//  RichPasteNetworkTests.swift
//  NoteCodeTests
//
//  Pasting HTML must not reach the network. The HTML import RichPaste uses
//  is WebKit's, which loads what a page refers to; a page copied from a
//  browser refers to images and stylesheets on its own servers, so a paste
//  would tell them the note was being written. A listener on 127.0.0.1
//  stands in for those servers and counts what reaches it.
//

#if canImport(UIKit)
import Testing
import Foundation
import Network
import UIKit
import UniformTypeIdentifiers
@testable import NoteCode

@Suite("Rich paste: HTML reaches no server", .serialized, .tags(.editor))
@MainActor
struct RichPasteNetworkTests {

    /// A local HTTP listener that records the first line of every request
    /// and answers each with an empty 404.
    final class Listener: @unchecked Sendable {
        private let listener: NWListener
        private let lock = NSLock()
        private var lines: [String] = []
        private let queue = DispatchQueue(label: "RichPasteNetworkTests.Listener")

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        }

        var requests: [String] { lock.withLock { lines } }

        /// Starts listening and returns the port it was given.
        func start() async throws -> UInt16 {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
                // The handler runs on `queue` only, so the flag needs no lock.
                nonisolated(unsafe) var resumed = false
                listener.stateUpdateHandler = { [listener] state in
                    guard !resumed else { return }
                    switch state {
                    case .ready:
                        resumed = true
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    case .failed(let error):
                        resumed = true
                        continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.start(queue: queue)
            }
        }

        func stop() { listener.cancel() }

        private func serve(_ connection: NWConnection) {
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
                let head = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let line = head.components(separatedBy: "\r\n").first ?? ""
                self?.lock.withLock { self?.lines.append(line.isEmpty ? "(connection)" : line) }
                let reply = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    /// How a sample's text becomes the bytes on the pasteboard.
    enum Bytes: Sendable {
        case utf8
        case utf16(bigEndian: Bool, bom: Bool)

        func data(_ text: String) -> Data {
            switch self {
            case .utf8: return Data(text.utf8)
            case let .utf16(bigEndian, bom):
                var data = Data(bom ? (bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]) : [])
                data += text.data(using: bigEndian ? .utf16BigEndian : .utf16LittleEndian)!
                return data
            }
        }
    }

    /// Each way a page can refer to something on a server, as HTML with
    /// `PORT` where the listener's port goes. What is between `⟦` and `⟧`
    /// is written in base64, after `PORT` is filled in.
    nonisolated static let vectors: [(name: String, html: String, bytes: Bytes)] = [
        ("img src", #"<p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/pixel.png">"#, .utf8),
        ("img srcset", #"<p>Hello <b>bold</b></p><img srcset="http://127.0.0.1:PORT/srcset.png 2x">"#, .utf8),
        ("link stylesheet", #"<html><head><link rel="stylesheet" href="http://127.0.0.1:PORT/style.css"></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("@import", #"<html><head><style>@import url("http://127.0.0.1:PORT/import.css");</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("background-image", #"<p style="background-image: url('http://127.0.0.1:PORT/background.png')">Hello <b>bold</b></p>"#, .utf8),
        ("style block url", #"<html><head><style>p { background: url(http://127.0.0.1:PORT/block.png) }</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("font-face", #"<html><head><style>@font-face { font-family: X; src: url(http://127.0.0.1:PORT/font.woff) } p { font-family: X }</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("iframe", #"<p>Hello <b>bold</b></p><iframe src="http://127.0.0.1:PORT/frame.html"></iframe>"#, .utf8),
        ("script", #"<p>Hello <b>bold</b></p><script src="http://127.0.0.1:PORT/script.js"></script>"#, .utf8),
        ("body background", #"<body background="http://127.0.0.1:PORT/body.png"><p>Hello <b>bold</b></p></body>"#, .utf8),
        ("input image", #"<p>Hello <b>bold</b></p><input type="image" src="http://127.0.0.1:PORT/input.png">"#, .utf8),
        ("video poster", #"<p>Hello <b>bold</b></p><video poster="http://127.0.0.1:PORT/poster.png"></video>"#, .utf8),
        ("object data", #"<p>Hello <b>bold</b></p><object data="http://127.0.0.1:PORT/object.png"></object>"#, .utf8),
        ("svg image", #"<p>Hello <b>bold</b></p><svg><image href="http://127.0.0.1:PORT/svg.png"/></svg>"#, .utf8),
        ("meta refresh", #"<html><head><meta http-equiv="refresh" content="0; url=http://127.0.0.1:PORT/refresh"></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("link prefetch", #"<html><head><link rel="prefetch" href="http://127.0.0.1:PORT/prefetch"><link rel="icon" href="http://127.0.0.1:PORT/icon.png"></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("entity-spelt url", #"<p style="background-image: u&#114;l(http://127.0.0.1:PORT/entity.png)">Hello <b>bold</b></p>"#, .utf8),
        ("escape-spelt url", #"<p style="background-image: u\72l(http://127.0.0.1:PORT/escape.png)">Hello <b>bold</b></p>"#, .utf8),
        ("base and relative img", #"<html><head><base href="http://127.0.0.1:PORT/"></head><body><p>Hello <b>bold</b></p><img src="relative.png"></body></html>"#, .utf8),
        // What the rebuild keeps (class, id, a noscript's markup, a declared
        // charset, a named reference in an address) can't bring a loader back.
        ("noscript img", #"<p>Hello <b>bold</b></p><noscript><img src="http://127.0.0.1:PORT/noscript.png"></noscript>"#, .utf8),
        ("class and id rules", #"<html><head><style>.x { background: url(http://127.0.0.1:PORT/class.png) } #y { background-image: url(http://127.0.0.1:PORT/id.png) }</style></head><body><p class="x" id="y">Hello <b>bold</b></p></body></html>"#, .utf8),
        ("declared charset", #"<meta charset="windows-1252"><p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/charset.png">"#, .utf8),
        ("named reference in a style", #"<p style="background-image: url&lpar;http://127.0.0.1:PORT/lpar.png&rpar;; font-family: caf&eacute;">Hello <b>bold</b></p>"#, .utf8),

        // CSS functions and properties that take an image or a resource.
        ("css image()", #"<p style="background-image: image('http://127.0.0.1:PORT/image-fn.png')">Hello <b>bold</b></p>"#, .utf8),
        ("css cross-fade()", #"<p style="background-image: cross-fade(url(http://127.0.0.1:PORT/xf-a.png), url(http://127.0.0.1:PORT/xf-b.png), 50%)">Hello <b>bold</b></p>"#, .utf8),
        ("css -webkit-cross-fade()", #"<p style="background-image: -webkit-cross-fade(url(http://127.0.0.1:PORT/wxf-a.png), url(http://127.0.0.1:PORT/wxf-b.png), 50%)">Hello <b>bold</b></p>"#, .utf8),
        ("css -webkit-image-set() strings", #"<p style="background-image: -webkit-image-set('http://127.0.0.1:PORT/wset.png' 1x, 'http://127.0.0.1:PORT/wset2.png' 2x)">Hello <b>bold</b></p>"#, .utf8),
        ("css image-set() strings", #"<p style="background-image: image-set('http://127.0.0.1:PORT/set.png' 1x)">Hello <b>bold</b></p>"#, .utf8),
        ("css cursor", #"<p style="cursor: url(http://127.0.0.1:PORT/cursor.png), auto">Hello <b>bold</b></p>"#, .utf8),
        ("css list-style-image", #"<ul style="list-style-image: url(http://127.0.0.1:PORT/bullet.png)"><li>Hello <b>bold</b></li></ul>"#, .utf8),
        ("css list-style shorthand", #"<html><head><style>li { list-style: square url(http://127.0.0.1:PORT/bullet2.png) inside }</style></head><body><ul><li>Hello <b>bold</b></li></ul></body></html>"#, .utf8),
        ("css content", #"<html><head><style>p::before { content: url(http://127.0.0.1:PORT/before.png) } p::after { content: image-set('http://127.0.0.1:PORT/after.png' 1x) }</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("css mask and mask-image", #"<p style="mask: url(http://127.0.0.1:PORT/mask.svg); mask-image: url(http://127.0.0.1:PORT/mask-image.png); -webkit-mask-image: url(http://127.0.0.1:PORT/wmask.png); -webkit-mask-box-image: url(http://127.0.0.1:PORT/wmaskbox.png)">Hello <b>bold</b></p>"#, .utf8),
        ("css border-image", #"<p style="border: 10px solid; border-image: url(http://127.0.0.1:PORT/border.png) 30 round; -webkit-border-image: url(http://127.0.0.1:PORT/wborder.png) 30 round">Hello <b>bold</b></p>"#, .utf8),
        ("css filter and clip-path", #"<p style="filter: url(http://127.0.0.1:PORT/filter.svg#f); clip-path: url(http://127.0.0.1:PORT/clip.svg#c); shape-outside: url(http://127.0.0.1:PORT/shape.png)">Hello <b>bold</b></p>"#, .utf8),
        ("css @namespace", #"<html><head><style>@namespace svg url(http://127.0.0.1:PORT/namespace); @namespace "http://127.0.0.1:PORT/namespace2"; p { color: red }</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("css @font-face local then url", #"<html><head><style>@font-face { font-family: Y; src: local(NoSuchFontAnywhere), url(http://127.0.0.1:PORT/local-then-url.woff2) format("woff2") } p { font-family: Y }</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("css @import string", #"<html><head><style>@import "http://127.0.0.1:PORT/import-string.css";</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("css comment around url", #"<html><head><style>p { background:/**/url(/**/"http://127.0.0.1:PORT/comment.png"/**/) } b { background: url( 'http://127.0.0.1:PORT/spaced.png' ) }</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("css escapes", #"<html><head><style>p { background: \75 rl(http://127.0.0.1:PORT/hex-esc.png) } b { background: u\rl(http://127.0.0.1:PORT/char-esc.png) } i { background: url(http\3a //127.0.0.1:PORT/in-url.png) } @\69mport url(http://127.0.0.1:PORT/esc-import.css);</style></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("uppercase and mixed case", #"<HTML><HEAD><STYLE>@IMPORT URL(HTTP://127.0.0.1:PORT/UPPER.CSS); P { BACKGROUND: Url(HTTP://127.0.0.1:PORT/MIXED.PNG) }</STYLE><LINK REL="STYLESHEET" HREF="HTTP://127.0.0.1:PORT/UPPERLINK.CSS"></HEAD><BODY><P STYLE="BACKGROUND-IMAGE: URL(HTTP://127.0.0.1:PORT/UPPERSTYLE.PNG)">Hello <B>bold</B></P><IMG SRC="HTTP://127.0.0.1:PORT/UPPER.PNG"><ImG sRc="hTtP://127.0.0.1:PORT/mixed.png"></BODY></HTML>"#, .utf8),
        ("unquoted attributes", #"<p style=background-image:url(http://127.0.0.1:PORT/unquoted-style.png)>Hello <b>bold</b></p><img src=http://127.0.0.1:PORT/unquoted.png><link rel=stylesheet href=http://127.0.0.1:PORT/unquoted.css>"#, .utf8),
        ("form feed and vertical tab", "<p\u{0C}style=\"background:\u{0C}url(http://127.0.0.1:PORT/ff-style.png)\">Hello <b>bold</b></p><img\u{0C}src=\"http://127.0.0.1:PORT/ff.png\"><img\u{0B}src=\"http://127.0.0.1:PORT/vt.png\"><p style=\"background:\u{0B}url(http://127.0.0.1:PORT/vt-style.png)\">x</p>", .utf8),

        // Relative references against a base.
        ("base and relative stylesheet", #"<html><head><base href="http://127.0.0.1:PORT/"><link rel="stylesheet" href="base.css"><style>@import "base-import.css"; p { background: url(base-url.png) }</style></head><body><p style="background-image: url(base-inline.png)">Hello <b>bold</b></p></body></html>"#, .utf8),
        ("scheme-relative base", #"<html><head><base href="//127.0.0.1:PORT/"></head><body><p>Hello <b>bold</b></p><img src="sr.png"><iframe src="sr.html"></iframe></body></html>"#, .utf8),

        // Elements that fetch.
        ("picture source srcset", #"<p>Hello <b>bold</b></p><picture><source srcset="http://127.0.0.1:PORT/source.png 1x" type="image/png"><img src="http://127.0.0.1:PORT/picture-fallback.png"></picture>"#, .utf8),
        ("audio", #"<p>Hello <b>bold</b></p><audio src="http://127.0.0.1:PORT/audio.mp3" preload="auto" autoplay></audio><audio preload="auto"><source src="http://127.0.0.1:PORT/audio-source.mp3"></audio>"#, .utf8),
        ("video and track", #"<p>Hello <b>bold</b></p><video src="http://127.0.0.1:PORT/video.mp4" preload="auto"><track default kind="captions" src="http://127.0.0.1:PORT/track.vtt"></video>"#, .utf8),
        ("embed", #"<p>Hello <b>bold</b></p><embed src="http://127.0.0.1:PORT/embed.svg" type="image/svg+xml">"#, .utf8),
        ("a ping", #"<p><a href="note.html" ping="http://127.0.0.1:PORT/ping">Hello <b>bold</b></a></p>"#, .utf8),
        ("link preload family", #"<html><head><link rel="preload" as="image" href="http://127.0.0.1:PORT/preload.png"><link rel="preload" as="style" href="http://127.0.0.1:PORT/preload.css"><link rel="modulepreload" href="http://127.0.0.1:PORT/module.js"><link rel="dns-prefetch" href="http://127.0.0.1:PORT/"><link rel="preconnect" href="http://127.0.0.1:PORT/"><link rel="apple-touch-icon" href="http://127.0.0.1:PORT/touch.png"></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),

        // SVG.
        ("svg use href", #"<p>Hello <b>bold</b></p><svg><use href="http://127.0.0.1:PORT/use.svg#x"/></svg>"#, .utf8),
        ("svg xlink:href", #"<p>Hello <b>bold</b></p><svg xmlns:xlink="http://www.w3.org/1999/xlink"><use xlink:href="http://127.0.0.1:PORT/xuse.svg#x"/><image xlink:href="http://127.0.0.1:PORT/ximage.png" width="10" height="10"/></svg>"#, .utf8),
        ("svg feImage", #"<p>Hello <b>bold</b></p><svg width="10" height="10"><filter id="f"><feImage href="http://127.0.0.1:PORT/feimage.png"/></filter><rect filter="url(#f)" width="10" height="10"/></svg>"#, .utf8),
        ("svg style", #"<p>Hello <b>bold</b></p><svg width="10" height="10"><style>@import url(http://127.0.0.1:PORT/svg-import.css); rect { fill: url(http://127.0.0.1:PORT/svg-fill.svg#p) }</style><rect width="10" height="10"/></svg>"#, .utf8),
        ("svg attribute url", #"<p>Hello <b>bold</b></p><svg width="10" height="10"><rect fill="url(http://127.0.0.1:PORT/svg-attr.svg#p)" width="10" height="10"/></svg>"#, .utf8),

        // data: URLs whose content refers to a server.
        ("data svg in img", #"<p>Hello <b>bold</b></p><img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Cimage href='http://127.0.0.1:PORT/data-svg.png' width='10' height='10'/%3E%3C/svg%3E">"#, .utf8),
        ("base64 data svg in img", #"<p>Hello <b>bold</b></p><img src="data:image/svg+xml;base64,⟦<svg xmlns='http://www.w3.org/2000/svg'><image href='http://127.0.0.1:PORT/b64-img-svg.png' width='10' height='10'/></svg>⟧">"#, .utf8),
        ("base64 data svg in object", #"<p>Hello <b>bold</b></p><object type="image/svg+xml" data="data:image/svg+xml;base64,⟦<svg xmlns='http://www.w3.org/2000/svg'><image href='http://127.0.0.1:PORT/b64-object-svg.png' width='10' height='10'/></svg>⟧"></object>"#, .utf8),
        ("base64 data svg in embed", #"<p>Hello <b>bold</b></p><embed type="image/svg+xml" src="data:image/svg+xml;base64,⟦<svg xmlns='http://www.w3.org/2000/svg'><image href='http://127.0.0.1:PORT/b64-embed-svg.png' width='10' height='10'/></svg>⟧">"#, .utf8),
        ("base64 data html in iframe", #"<p>Hello <b>bold</b></p><iframe src="data:text/html;base64,⟦<img src='http://127.0.0.1:PORT/b64-iframe.png'><link rel=stylesheet href='http://127.0.0.1:PORT/b64-iframe.css'>⟧"></iframe>"#, .utf8),
        ("base64 data css in link", #"<html><head><link rel="stylesheet" href="data:text/css;base64,⟦@import url(http://127.0.0.1:PORT/b64-link-import.css); p { background: url(http://127.0.0.1:PORT/b64-link-bg.png) }⟧"></head><body><p>Hello <b>bold</b></p></body></html>"#, .utf8),
        ("base64 data svg in a style", #"<p style="background-image: url(data:image/svg+xml;base64,⟦<svg xmlns='http://www.w3.org/2000/svg'><image href='http://127.0.0.1:PORT/b64-style-svg.png' width='10' height='10'/></svg>⟧)">Hello <b>bold</b></p>"#, .utf8),

        // file: URLs (a request can't reach the listener; these show what
        // mayLoad says, and are here so a scheme change is seen).
        ("file urls", #"<p style="background-image: url(file:///System/Library/Desktop%20Pictures/none.png)">Hello <b>bold</b></p><img src="file:/System/Library/none.png"><link rel="stylesheet" href="file:/System/Library/none.css">"#, .utf8),

        // Encodings and charsets.
        ("utf-16le with bom", #"<p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/u16le-bom.png">"#, .utf16(bigEndian: false, bom: true)),
        ("utf-16be with bom", #"<p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/u16be-bom.png">"#, .utf16(bigEndian: true, bom: true)),
        ("utf-16le without bom", #"<p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/u16le.png"><p style="background:url(http://127.0.0.1:PORT/u16le-style.png)">x</p>"#, .utf16(bigEndian: false, bom: false)),
        ("utf-16be without bom", #"<p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/u16be.png">"#, .utf16(bigEndian: true, bom: false)),
        ("meta charset utf-16 on ascii", #"<meta charset="utf-16"><p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/meta-utf16.png">"#, .utf8),
        ("content-type charset iso-8859-1", #"<html><head><meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1"></head><body><p>Caf\#u{E9} Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/latin1.png"></body></html>"#, .utf8),
        ("meta charset shift_jis", #"<meta charset="shift_jis"><p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/sjis.png">"#, .utf8),
        ("meta charset x-user-defined", #"<meta charset="x-user-defined"><p>Hello <b>bold</b></p><img src="http://127.0.0.1:PORT/xud.png">"#, .utf8),
        ("meta charset utf-7", #"<meta charset="utf-7"><p>Hello <b>bold</b></p>+ADw-img src+AD0AIg-http+ADoALwAv-127.0.0.1+ADo-PORT+AC8-utf7.png+ACIAPg-"#, .utf8),

        // Character references without their semicolons.
        ("numeric references without semicolons", #"<p style="background-image: u&#114l(http://127.0.0.1:PORT/nosemi-dec.png); border-image: &#x75rl(http://127.0.0.1:PORT/nosemi-hex.png) 30">Hello <b>bold</b></p><img src="&#104ttp&#58&#47&#47127.0.0.1:PORT/nosemi-img.png">"#, .utf8),
    ]

    nonisolated static var vectorNames: [String] { vectors.map(\.name) }

    /// Sample `name`'s bytes, for a listener on `port`. `prefix` goes before
    /// each address's path, so one listener can tell samples apart.
    static func sample(_ name: String, port: UInt16, prefix: String = "") throws -> Data {
        let vector = try #require(vectors.first { $0.name == name })
        var html = vector.html.replacingOccurrences(of: "PORT", with: "\(port)\(prefix)")
        while let open = html.firstIndex(of: "⟦"), let close = html[open...].firstIndex(of: "⟧") {
            let inner = String(html[html.index(after: open)..<close])
            html.replaceSubrange(open...close, with: Data(inner.utf8).base64EncodedString())
        }
        return vector.bytes.data(html)
    }

    /// A pasteboard of its own holding `items`, removed when `body` ends.
    static func withPasteboard<T>(_ items: [String: Any], _ body: (UIPasteboard) async throws -> T) async throws -> T {
        let pasteboard = try #require(UIPasteboard(name: UIPasteboard.Name("RichPasteNetworkTests.\(UUID().uuidString)"), create: true))
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.setItems([items])
        return try await body(pasteboard)
    }

    static func rtf(_ text: String, bold: String) throws -> Data {
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: UIFont(name: "Helvetica", size: 12)!])
        attributed.append(NSAttributedString(string: bold, attributes: [.font: UIFont(name: "Helvetica-Bold", size: 12)!]))
        return try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    @Test("RTF beside HTML that refers to a server isn't read, and nothing is fetched")
    func rtfBesideLoadingHTML() async throws {
        let listener = try Listener()
        let port = try await listener.start()
        defer { listener.stop() }
        let html = #"<p>From the <b>page</b></p><img src="http://127.0.0.1:\#(port)/pixel.png">"#
        let markdown = try await Self.withPasteboard([
            UTType.rtf.identifier: try Self.rtf("From the ", bold: "rtf"), UTType.html.identifier: Data(html.utf8),
        ]) { RichPaste.markdown(from: $0, atLineStart: true) }
        let reached = await waitFor({ !listener.requests.isEmpty }, seconds: 2)
        #expect(!reached, "the paste reached the server: \(listener.requests)")
        #expect(markdown?.trimmingCharacters(in: .newlines) == "From the **page**", "the HTML was read, rebuilt")
    }

    @Test("RTF beside HTML that refers to nothing is still read first, for its lists")
    func rtfBesideQuietHTML() async throws {
        let markdown = try await Self.withPasteboard([
            UTType.rtf.identifier: try Self.rtf("\t•\tOne\n\t•\tTwo ", bold: "rtf"),
            UTType.html.identifier: Data("<ul><li>One</li><li>Two <b>html</b></li></ul>".utf8),
        ]) { RichPaste.markdown(from: $0, atLineStart: true) }
        #expect(markdown == "- One\n- Two **rtf**")
    }

    @Test("Pasting HTML that refers to a server sends it nothing, and keeps the formatting", arguments: vectorNames)
    func noRequests(vector: String) async throws {
        let listener = try Listener()
        let port = try await listener.start()
        defer { listener.stop() }
        try #require(port != 0)

        let html = try Self.sample(vector, port: port)
        // The pasteboard offers RTF and RTFD made from the HTML as well, and
        // making them was what fetched first (18 Nov).
        let markdown = try await Self.withPasteboard([UTType.html.identifier: html]) {
            RichPaste.markdown(from: $0, atLineStart: true)
        }

        // A load may land after the import returns; give it a bounded while.
        let reached = await waitFor({ !listener.requests.isEmpty }, seconds: 2)
        #expect(!reached, "\(vector): the paste reached the server: \(listener.requests)")
        #expect(markdown?.contains("**bold**") == true, "\(vector): the formatting was lost: \(markdown ?? "nil")")
    }

    /// Paths the listener was asked for, by sample: each sample's addresses
    /// start `/v<index>/`.
    static func reachedSamples(_ requests: [String]) -> [String] {
        vectors.indices.filter { index in requests.contains { $0.contains("/v\(index)/") } }.map { vectors[$0].name }
            + (requests.contains { !$0.contains("/v") } ? ["(unattributed: \(requests))"] : [])
    }

    @Test("HTML mayLoad calls quiet loads nothing, read as it is, through the import or the pasteboard's RTF")
    func quietMeansQuiet() async throws {
        let listener = try Listener()
        let port = try await listener.start()
        defer { listener.stop() }
        var quiet: [String] = []
        for (index, vector) in Self.vectors.enumerated() {
            let html = try Self.sample(vector.name, port: port, prefix: "/v\(index)")
            guard !PastedHTML.mayLoad(html) else { continue }
            quiet.append(vector.name)
            // Not rebuilt: what mayLoad lets through reaches WebKit as it is
            // when the pasteboard makes RTF from it.
            _ = try? NSAttributedString(data: html, options: RichPaste.htmlOptions, documentAttributes: nil)
            try await Self.withPasteboard([UTType.html.identifier: html]) { pasteboard in
                _ = pasteboard.data(forPasteboardType: UTType.rtf.identifier)
                _ = pasteboard.data(forPasteboardType: UTType.flatRTFD.identifier)
            }
        }
        let reached = await waitFor({ !listener.requests.isEmpty }, seconds: 2)
        #expect(!reached, "quiet samples reached the server: \(Self.reachedSamples(listener.requests)) \(listener.requests)")
        print("RichPasteNetworkTests: mayLoad quiet for \(quiet)")
    }

    @Test("Rebuilt HTML, read again as it is or rebuilt again, loads nothing and keeps the bold")
    func rebuiltIsQuiet() async throws {
        let listener = try Listener()
        let port = try await listener.start()
        defer { listener.stop() }
        var lost: [String] = []
        for (index, vector) in Self.vectors.enumerated() {
            let once = PastedHTML.sanitised(try Self.sample(vector.name, port: port, prefix: "/v\(index)"))
            let twice = PastedHTML.sanitised(once)
            _ = try? NSAttributedString(data: once, options: RichPaste.htmlOptions, documentAttributes: nil)
            _ = try? NSAttributedString(data: twice, options: RichPaste.htmlOptions, documentAttributes: nil)
            let markdown = try await Self.withPasteboard([UTType.html.identifier: once]) { pasteboard in
                if !PastedHTML.mayLoad(once) {
                    _ = pasteboard.data(forPasteboardType: UTType.rtf.identifier)
                }
                return RichPaste.markdown(from: pasteboard, atLineStart: true)
            }
            if markdown?.contains("**bold**") != true { lost.append(vector.name) }
        }
        let reached = await waitFor({ !listener.requests.isEmpty }, seconds: 2)
        #expect(!reached, "rebuilt samples reached the server: \(Self.reachedSamples(listener.requests)) \(listener.requests)")
        #expect(lost.isEmpty, "the bold was lost pasting the rebuilt HTML of \(lost)")
    }

    /// RTF whose field asks for a picture on a server.
    static func includePictureRTF(port: UInt16) -> Data {
        Data(#"""
        {\rtf1\ansi\ansicpg1252{\fonttbl\f0\fswiss Helvetica;}\f0\fs24 Hello {\b bold}\par
        {\field{\*\fldinst{INCLUDEPICTURE "http://127.0.0.1:PORT/includepicture.png" \\d \\* MERGEFORMATINET}}{\fldrslt{x}}}\par
        {\field{\*\fldinst{INCLUDEPICTURE \\d "http://127.0.0.1:PORT/includepicture2.png"}}{\fldrslt{\pict\pngblip\picw1\pich1 00}}}\par
        {\field{\*\fldinst{IMPORT "http://127.0.0.1:PORT/import-field.png"}}{\fldrslt{y}}}\par
        {\field{\*\fldinst{INCLUDETEXT "http://127.0.0.1:PORT/includetext.txt"}}{\fldrslt{z}}}\par
        }
        """#.replacingOccurrences(of: "PORT", with: "\(port)").utf8)
    }

    @Test("RTF on its own whose field includes a picture from a server fetches nothing", arguments: [false, true])
    func rtfIncludePicture(besideQuietHTML: Bool) async throws {
        let listener = try Listener()
        let port = try await listener.start()
        defer { listener.stop() }
        var items: [String: Any] = [UTType.rtf.identifier: Self.includePictureRTF(port: port)]
        if besideQuietHTML { items[UTType.html.identifier] = Data("<p>Hello <b>html</b></p>".utf8) }
        let markdown = try await Self.withPasteboard(items) { RichPaste.markdown(from: $0, atLineStart: true) }
        let reached = await waitFor({ !listener.requests.isEmpty }, seconds: 2)
        #expect(!reached, "the paste reached the server: \(listener.requests)")
        #expect(markdown?.contains("**bold**") == true, "the formatting was lost: \(markdown ?? "nil")")
    }

    @Test("HTML beside a web archive from a server fetches nothing, whatever the archive refers to", arguments: ["quiet", "loading", "none"])
    func htmlBesideWebArchive(html kind: String) async throws {
        let listener = try Listener()
        let port = try await listener.start()
        defer { listener.stop() }
        let page = #"<html><body><p>Hello <b>bold</b></p><img src="archive-relative.png"><img src="http://127.0.0.1:PORT/archive-absolute.png"><link rel="stylesheet" href="archive.css"></body></html>"#
            .replacingOccurrences(of: "PORT", with: "\(port)")
        let archive = try PropertyListSerialization.data(fromPropertyList: [
            "WebMainResource": [
                "WebResourceData": Data(page.utf8),
                "WebResourceFrameName": "",
                "WebResourceMIMEType": "text/html",
                "WebResourceTextEncodingName": "UTF-8",
                "WebResourceURL": "http://127.0.0.1:\(port)/archive/page.html",
            ],
        ], format: .binary, options: 0)
        // The HTML beside it refers to nothing, to a server, or isn't there.
        var items: [String: Any] = [UTType.webArchive.identifier: archive]
        switch kind {
        case "quiet": items[UTType.html.identifier] = Data(#"<p>Hello <b>bold</b></p><img src="html-relative.png">"#.utf8)
        case "loading": items[UTType.html.identifier] = Data(#"<p>Hello <b>bold</b></p><img src="http://127.0.0.1:\#(port)/html-absolute.png">"#.utf8)
        default: break
        }
        let markdown = try await Self.withPasteboard(items) { pasteboard in
            RichPaste.markdown(from: pasteboard, atLineStart: true)
        }
        let reached = await waitFor({ !listener.requests.isEmpty }, seconds: 2)
        #expect(!reached, "the paste reached the server: \(listener.requests)")
        #expect(markdown?.contains("**bold**") == true, "the formatting was lost: \(markdown ?? "nil")")
    }
}
#endif
