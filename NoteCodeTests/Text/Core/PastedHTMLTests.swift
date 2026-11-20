//
//  PastedHTMLTests.swift
//  NoteCodeTests
//
//  Pasted HTML rebuilt so that reading it loads nothing (PastedHTML). The
//  network side, with WebKit reading the result, is RichPasteNetworkTests.
//

import Testing
import Foundation
@testable import NoteCode

@Suite("Pasted HTML: rebuilt to load nothing", .tags(.editor))
struct PastedHTMLTests {

    static func clean(_ html: String) -> String {
        String(decoding: PastedHTML.sanitised(Data(html.utf8)), as: UTF8.self)
    }

    /// Whether `css` still has a function that loads: one not renamed.
    static func loads(_ css: String) -> Bool {
        let lowered = css.lowercased()
        return ["url(", "image-set(", "src(", "@import"].contains { lowered.replacingOccurrences(of: "invalid-" + $0, with: "").replacingOccurrences(of: "@invalid-import", with: "").contains($0) }
    }

    @Test("Formatting tags, a link and inline styles are kept")
    func keepsFormatting() {
        #expect(Self.clean(#"<p>See <b>bold</b>, <i>slant</i> and <a href="https://example.com/?a=1&amp;b=2">a link</a></p>"#)
            == #"<p>See <b>bold</b>, <i>slant</i> and <a href="https://example.com/?a=1&amp;b=2">a link</a></p>"#)
        #expect(Self.clean(#"<span style="color: red; font-weight: 700">red</span>"#)
            == #"<span style="color: red; font-weight: 700">red</span>"#)
        #expect(Self.clean("<pre><code>a &lt; b</code></pre>") == "<pre><code>a &lt; b</code></pre>")
    }

    @Test("Elements that load something go, and so do the attributes")
    func dropsLoaders() {
        #expect(Self.clean(#"<p>a</p><img src="http://x/p.png" srcset="http://x/q.png 2x"><video poster="http://x/v.png"></video>"#)
            == "<p>a</p>")
        #expect(Self.clean(#"<html><head><link rel="stylesheet" href="http://x/s.css"><base href="http://x/"><meta charset="utf-8"></head><body background="http://x/b.png">b</body></html>"#)
            == "<html><head></head><body>b</body></html>")
        #expect(Self.clean(#"<p>a</p><script src="http://x/s.js">alert(1)</script><iframe src="http://x/f"></iframe><!-- <img src=x> -->"#)
            == "<p>a</p>")
        #expect(Self.clean(#"<svg><image href="http://x/i.png"/></svg>c"#) == "c")
    }

    @Test("A style can't load: url, image-set, src and @import, however they're spelt")
    func safeStyles() {
        let attribute = Self.clean(#"<p style="background: url('http://x/a.png'); color: blue">a</p>"#)
        #expect(!Self.loads(attribute), "\(attribute)")
        #expect(attribute.contains("color: blue"))
        let entity = Self.clean(#"<p style="background: u&#114;l(http://x/a.png)">a</p>"#)
        #expect(!Self.loads(entity), "an entity spelt it: \(entity)")
        let escape = Self.clean(#"<p style="background: u\72l(http://x/a.png)">a</p>"#)
        #expect(!escape.contains("\\"), "a CSS escape spelt it: \(escape)")
        let block = Self.clean(#"<style>@IMPORT "http://x/i.css"; p { background: URL(http://x/b.png); b: -webkit-image-set("http://x/c.png" 1x) } @font-face { src: url(http://x/f.woff) }</style>"#)
        #expect(!Self.loads(block), "\(block)")
        #expect(block.contains("@invalid-import") && block.contains("invalid-URL(") && block.contains("-webkit-invalid-image-set("), "\(block)")
    }

    @Test("A value is written back escaped, so it can't end its quotes or open a tag")
    func escapesValues() {
        #expect(Self.clean(#"<a href='x"><img src=y>'>t</a>"#) == #"<a href="x&quot;>&lt;img src=y>">t</a>"#)
        #expect(Self.clean("a < b <3") == "a &lt; b &lt;3")
    }

    @Test("A tag the text ends inside is dropped, with the rest")
    func unfinished() {
        #expect(Self.clean(#"<b>a</b><img src="http://x/p.png"#) == "<b>a</b>")
    }

    @Test("UTF-16 with a byte order mark is read as UTF-16, and comes out as UTF-8")
    func encodings() throws {
        let utf16 = try #require("<b>é</b>".data(using: .utf16))
        #expect(String(decoding: PastedHTML.sanitised(utf16), as: UTF8.self) == "<b>é</b>")
        #expect(String(decoding: PastedHTML.sanitised(Data([0xEF, 0xBB, 0xBF]) + Data("<b>é</b>".utf8)), as: UTF8.self) == "<b>é</b>")
    }

    @Test("A class and an id are kept, so a style block's rules still find what they style")
    func keepsClassAndID() {
        // The Cocoa HTML Writer (Notes, Pages, TextEdit) puts every style in
        // class rules: without `class`, all its formatting went.
        #expect(Self.clean(#"<style>span.s1 {font-weight: bold}</style><p class="p1"><span class="s1" id="x">b</span></p>"#)
            == #"<style>span.s1 {font-weight: bold}</style><p class="p1"><span class="s1" id="x">b</span></p>"#)
    }

    @Test("HTML in a charset its meta names is read in it, and comes out as UTF-8")
    func declaredCharset() {
        var latin = Data(#"<meta charset="windows-1252"><p>Caf"#.utf8) + Data([0xE9]) + Data(" na".utf8) + Data([0xEF]) + Data("ve</p>".utf8)
        #expect(String(decoding: PastedHTML.sanitised(latin), as: UTF8.self) == "<p>Caf\u{E9} na\u{EF}ve</p>")
        latin = Data(#"<meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1"><p>Caf"#.utf8) + Data([0xE9, 0x3C]) + Data("/p>".utf8)
        #expect(String(decoding: PastedHTML.sanitised(latin), as: UTF8.self) == "<p>Caf\u{E9}</p>")
        // A name no one knows leaves the bytes as they are.
        #expect(String(decoding: PastedHTML.sanitised(Data(#"<meta charset="nonsense"><p>Caf\#u{E9}</p>"#.utf8)), as: UTF8.self) == "<p>Caf\u{E9}</p>")
    }

    @Test("UTF-16 with no byte order mark is read as UTF-16, either end first")
    func utf16WithoutMark() throws {
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let html = try #require("<p>Hello <b>bold</b></p>".data(using: encoding))
            #expect(String(decoding: PastedHTML.sanitised(html), as: UTF8.self) == "<p>Hello <b>bold</b></p>")
        }
    }

    @Test("A meta naming UTF-16 on ASCII bytes means UTF-8, and x-user-defined windows-1252, as in a browser")
    func browserCharsetOverrides() {
        #expect(Self.clean(#"<meta charset="utf-16"><p>Hello <b>bold</b></p>"#) == "<p>Hello <b>bold</b></p>")
        #expect(Self.clean(#"<meta charset="UTF-16LE"><p>Hello <b>bold</b></p>"#) == "<p>Hello <b>bold</b></p>")
        let latin = Data(#"<meta charset="x-user-defined"><p>Caf"#.utf8) + Data([0xE9]) + Data("</p>".utf8)
        #expect(String(decoding: PastedHTML.sanitised(latin), as: UTF8.self) == "<p>Caf\u{E9}</p>")
    }

    @Test("A data: address might load, base64 or not: its content can refer to a server")
    func dataMayLoad() {
        let css = Data("@import url(http://x/s.css);".utf8).base64EncodedString()
        #expect(PastedHTML.mayLoad(Data(#"<link rel="stylesheet" href="data:text/css;base64,\#(css)"><p>a</p>"#.utf8)))
        #expect(PastedHTML.mayLoad(Data(#"<iframe src="DATA:text/html;base64,PGltZz4="></iframe>"#.utf8)))
        #expect(PastedHTML.mayLoad(Data(#"<object data="d&#97;ta&colon;image/svg+xml;base64,PHN2Zz4="></object>"#.utf8)))
    }

    @Test("An address the declared charset spells is seen too")
    func declaredCharsetMayLoad() throws {
        let html = try #require(#"<meta charset="utf-16le"><img src="http://x/p.png">"#.data(using: .utf16LittleEndian))
        #expect(PastedHTML.mayLoad(html))
    }

    @Test("Text in a textarea is kept as text, and what a noscript holds is read as markup")
    func visibleRawText() {
        #expect(Self.clean("<p>a</p><textarea>int x = a &lt; b; <b>c</b></textarea>") == "<p>a</p>int x = a &lt; b; &lt;b>c&lt;/b>")
        #expect(Self.clean(#"<noscript><p>Enable <b>JS</b><img src="http://x/p.png"></p></noscript>"#) == "<p>Enable <b>JS</b></p>")
    }

    @Test("A named reference that can't spell punctuation is left for the import to read")
    func namedReferences() {
        #expect(Self.clean(#"<a href="https://x.com/caf&eacute;">c</a>"#) == #"<a href="https://x.com/caf&eacute;">c</a>"#)
        // `&amp;` written out stays an ampersand, not the start of a reference.
        #expect(Self.clean(#"<a href="https://x.com/?a&amp;eacute;">c</a>"#) == #"<a href="https://x.com/?a&amp;eacute;">c</a>"#)
        #expect(Self.clean(#"<a href="https://x.com/&colon;">c</a>"#) == #"<a href="https://x.com/:">c</a>"#)
        // In a style every reference is read first, so a name can't hide a loader.
        #expect(Self.clean(#"<p style="font-family: caf&eacute;">c</p>"#) == #"<p style="font-family: caf&amp;eacute;">c</p>"#)
    }

    // MARK: Whether HTML as it is might load

    static func mayLoad(_ html: String) -> Bool { PastedHTML.mayLoad(Data(html.utf8)) }

    @Test("HTML that refers to nothing on a server can't load, a leading doctype's address included")
    func refersToNothing() {
        #expect(!Self.mayLoad("<p>See <b>bold</b> and <span style=\"color: red\">red</span></p>"))
        // What Notes, Pages and NSAttributedString write.
        #expect(!Self.mayLoad(#"""
        <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
        <html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
        <style type="text/css">p.p1 {margin: 0.0px; font: 12.0px Helvetica}</style></head>
        <body><ul class="ul1"><li class="li1">One</li></ul></body></html>
        """#))
    }

    @Test("An address, however it is spelt, a resource in a style or a script might load")
    func refersToSomething() {
        for html in [
            #"<img src="http://x/p.png">"#, #"<img src="HTTPS://x/p.png">"#, #"<img src="//x/p.png">"#,
            #"<img src="http&colon;&sol;&sol;x/p.png">"#, #"<img src="h&#116;tp://x">"#, #"<img src="ht&Tab;tp://x">"#,
            "<img src=\"ht\ntp://x\">", #"<img src="\\x\p.png">"#, #"<p style="background: u\72l(x)">"#,
            #"<p style="background:url(p.png)">"#, #"<style>@IMPORT "s.css";</style>"#, "<script>fetch()</script>",
            #"<a href="https://example.com">a link</a>"#, #"<p>a</p><!DOCTYPE html><img src="http://x/p.png">"#,
        ] {
            #expect(Self.mayLoad(html), "\(html)")
        }
        #expect(PastedHTML.mayLoad(Data([0xFF, 0xFE, 0x3C, 0x00])), "UTF-16 isn't read")
    }
}
