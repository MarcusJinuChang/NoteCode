//
//  RichPasteHTMLTests.swift
//  NoteCodeTests
//
//  HTML that might load is read rebuilt (PastedHTML), never as it is and
//  never through the RTF the pasteboard makes from it. These are what the
//  rebuild must keep: what each source writes, read as the paste reads it.
//  That nothing is fetched is RichPasteNetworkTests.
//

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
import UniformTypeIdentifiers
@testable import NoteCode

@Suite("Rich paste: HTML read rebuilt keeps its formatting", .serialized, .tags(.editor))
@MainActor
struct RichPasteHTMLTests {

    static func paste(_ items: [String: Any]) throws -> String? {
        let pasteboard = try #require(UIPasteboard(name: UIPasteboard.Name("RichPasteHTMLTests.\(UUID().uuidString)"), create: true))
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.setItems([items])
        return RichPaste.markdown(from: pasteboard, atLineStart: true)?.trimmingCharacters(in: .newlines)
    }

    static func data(_ text: NSAttributedString, _ type: NSAttributedString.DocumentType) throws -> Data {
        try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: type])
    }

    /// What Notes, Pages and TextEdit write: one attributed string through
    /// the Cocoa writers, as RTF and as HTML, with a link in it.
    static func cocoaNote() throws -> NSAttributedString {
        let body = try #require(UIFont(name: "Helvetica", size: 12))
        let bold = try #require(UIFont(name: "Helvetica-Bold", size: 12))
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "Shopping\n", attributes: [.font: try #require(UIFont(name: "Helvetica-Bold", size: 18))]))
        text.append(NSAttributedString(string: "Milk ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "from here", attributes: [.font: body, .link: try #require(URL(string: "https://example.com/shop"))]))
        text.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        text.append(NSAttributedString(string: "Eggs", attributes: [.font: bold]))
        text.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        text.append(NSAttributedString(string: "Red words", attributes: [.font: body, .foregroundColor: UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)]))
        text.append(NSAttributedString(string: " and big words", attributes: [.font: try #require(UIFont(name: "Helvetica", size: 24))]))
        text.append(NSAttributedString(string: " and italic", attributes: [.font: try #require(UIFont(name: "Helvetica-Oblique", size: 12))]))
        text.append(NSAttributedString(string: " and struck", attributes: [.font: body, .strikethroughStyle: 1]))
        return text
    }

    @Test("A copy from Notes, Pages or TextEdit with a link keeps its formatting, which the HTML holds in class rules")
    func cocoaWriters() throws {
        let note = try Self.cocoaNote()
        let html = try Self.data(note, .html)
        #expect(String(decoding: html, as: UTF8.self).contains("class=\"s"), "the writer styles by class")
        let markdown = try Self.paste([UTType.rtf.identifier: try Self.data(note, .rtf), UTType.html.identifier: html])
        #expect(markdown == """
        <span style="font-size:1.5em">**Shopping**</span>
        Milk [from here](https://example.com/shop)
        **Eggs**
        <span style="color:#E61A1A">Red words</span><span style="font-size:2em"> and big words</span> *and italic* ~~and struck~~
        """, "\(markdown ?? "nil")")
    }

    @Test("A style block's class rules reach the spans that name them")
    func classRules() throws {
        let html = #"<html><head><style>.hl { color: #d01010; font-weight: bold }</style></head><body><p>See <a href="https://x.com">x</a> and <span class="hl">red bold</span></p></body></html>"#
        let markdown = try Self.paste([UTType.html.identifier: Data(html.utf8)])
        #expect(markdown == #"See [x](https://x.com/) and <span style="color:#D01010">**red bold**</span>"#, "\(markdown ?? "nil")")
    }

    @Test("HTML in the charset its meta names reads in that charset")
    func declaredCharset() throws {
        let html = Data(#"<meta charset="windows-1252"><p>Caf"#.utf8) + Data([0xE9]) + Data(" na".utf8) + Data([0xEF])
            + Data(#"ve <b>b</b> <a href="https://x.com">l</a></p>"#.utf8)
        let markdown = try Self.paste([UTType.html.identifier: html])
        #expect(markdown == "Caf\u{E9} na\u{EF}ve **b** [l](https://x.com/)", "\(markdown ?? "nil")")
    }

    @Test("A page over the HTML allowance that is small once rebuilt is still read")
    func largePage() throws {
        let script = "<script>" + String(repeating: "var a = 'https://x.com/tracker';\n", count: 14_000) + "</script>"
        let html = "<html><head>\(script)</head><body><p>Line <b>bold</b> <a href=\"https://x.com\">l</a></p></body></html>"
        try #require(html.utf8.count > RichPaste.maxHTMLBytes)
        let markdown = try Self.paste([
            UTType.rtf.identifier: try Self.data(NSAttributedString(string: "Line bold l"), .rtf), UTType.html.identifier: Data(html.utf8),
        ])
        #expect(markdown == "Line **bold** [l](https://x.com/)", "\(markdown ?? "nil")")
    }

    @Test("Text in a textarea is kept")
    func textarea() throws {
        let html = #"<p>See <a href="https://x.com">x</a>:</p><textarea>int main() { return 0; }</textarea><p>after</p>"#
        let markdown = try Self.paste([UTType.html.identifier: Data(html.utf8)])
        #expect(markdown?.contains("int main() { return 0; }") == true, "\(markdown ?? "nil")")
    }

    @Test("A named reference in a link's address is read")
    func namedReferenceInLink() throws {
        let markdown = try Self.paste([UTType.html.identifier: Data(#"<p><a href="https://x.com/caf&eacute;">cafe</a> <b>b</b></p>"#.utf8)])
        #expect(markdown == "[cafe](https://x.com/caf%C3%A9) **b**", "\(markdown ?? "nil")")
    }
}
#endif
