//
//  TestNotes.swift
//  NoteCode
//
//  A folder of notes made to be tested against: every kind of text, code in
//  each language, formulas, room for ink, a long note and the edge cases, each
//  opening with a checklist of what to look at. Settings › Help and About ›
//  Add Test Notes makes them, in a Debug build or where the edition
//  says (`AppExtensions.isTestingBuild`).
//

import Foundation
import SwiftData

/// One note of the test set.
nonisolated struct TestNote: Equatable, Sendable, Identifiable {
    var title: String
    var content: String
    var orientation: PageOrientation = .portrait
    /// Opened read-only, to check the lock.
    var isTextLocked = false
    /// Filed in the set's inner folder, to check nesting and moving.
    var isNested = false

    var id: String { title }
}

/// The test set: text only, like the templates and the Welcome note, so each
/// note is just Markdown that the parser every note goes through reads.
///
/// Every note opens with **What to check**, a checklist to tick while testing.
/// Ticking edits the note; Add Test Notes again gives a fresh set beside it.
nonisolated enum TestNotes {
    static let folderName = "Test Notes"
    static let nestedFolderName = "More tests"

    static var all: [TestNote] {
        [
            TestNote(title: "Test 1 · Text and marks", content: text),
            TestNote(title: "Test 2 · Lists and checklists", content: lists),
            TestNote(title: "Test 3 · Code in every language", content: code),
            TestNote(title: "Test 4 · Formulas", content: formulas),
            TestNote(title: "Test 5 · Ink and the lasso", content: ink),
            TestNote(title: "Test 6 · Long note", content: long),
            TestNote(title: "Test 7 · Landscape", content: landscape, orientation: .landscape),
            TestNote(title: "Test 8 · Edge cases", content: edgeCases),
            TestNote(title: "Test 9 · Locked text", content: locked, isTextLocked: true),
            TestNote(title: "Test 10 · Empty", content: ""),
            TestNote(title: "Test 11 · In a nested folder", content: nested, isNested: true),
        ]
    }

    // MARK: - The notes

    static let text = #"""
        # Test 1 · Text and marks

        ## What to check

        - [ ] Markers hide when the caret leaves a line, and come back when it returns
        - [ ] Each swatch in the text row recolours a selected word, and the Default ring takes the colour off
        - [ ] The swatches look as bright on the page as in the row
        - [ ] + and − resize a selection; Undo puts it back in one step
        - [ ] Bold, italic, underline and strikethrough from the row, on a selection and as a typing style at a caret
        - [ ] Every highlight colour, and a coloured word inside a highlight
        - [ ] Links open; bracketed words that aren't links stay text
        - [ ] The outline lists every heading below, and a tap jumps to it
        - [ ] Show Markdown (Settings › Writing) shows every marker; the lookalikes stay text either way

        ## Headings

        # Heading 1
        ## Heading 2
        ### Heading 3
        #### Heading 4
        ##### Heading 5
        ###### Heading 6

        ## Inline marks

        Plain, **bold**, *italic*, ***bold italic***, <u>underline</u>, ~~struck~~ and `inline code`.

        Nested: **bold with *italic* inside**, *italic with `code` inside*, ~~struck **and bold**~~.

        A mark across words: **this whole phrase is bold** and then plain again.

        ## Colours

        <span style="color:#E5484D">Red</span>, <span style="color:#E5750A">Orange</span>, <span style="color:#B88700">Yellow</span>, <span style="color:#2F9E44">Green</span>, <span style="color:#3B82F6">Blue</span>, <span style="color:#9061F9">Purple</span>.

        <span style="color:#3B82F6">**Bold blue**</span>, <span style="color:#E5484D">*italic red*</span>, **<span style="color:#2F9E44">green inside bold</span>**.

        A colour from elsewhere, made legible on the page: <span style="color:#FFFF00">pure yellow</span>, <span style="color:#00FF00">pure green</span>.

        ## Sizes

        <span style="font-size:0.85em">Small (0.85em)</span>, normal, <span style="font-size:1.25em">large (1.25em)</span>, <span style="font-size:1.5em">larger (1.5em)</span>, <span style="font-size:2em">twice (2em)</span>.

        <span style="color:#9061F9;font-size:1.5em">Purple and large together</span>, then plain.

        ## Highlights

        ==🔴Red== ==🟠Orange== ==🟡Yellow== ==🟢Green== ==🔵Blue== ==🟣Purple==

        Two touching: ==🟡first====🔴second==. A coloured word inside one: ==🟢green <span style="color:#E5484D">red</span> green==.

        ## Links

        [Apple's developer site](https://developer.apple.com), and a bare address: https://www.swift.org

        Placeholders stay text: [Topic], [Course], [N].

        ## Quotes and rules

        > A quote of one line.

        > A quote long enough to wrap onto a second line and then a third, so the bar beside it has to stay one continuous stripe the whole way down.
        >> A nested quote.
        >>> Three deep.

        Above a rule.

        ---

        Below a rule.

        ## Lookalikes that must stay text

        a == b, x === y, ====, ===🟡 and == spaced ==.

        <span style="font-weight:bold">a span with another property</span> and <u>an unclosed underline.

        2 * 3 * 4 = 24, snake_case_name, __dunder__, and a lone * star.
        """#

    static let lists = #"""
        # Test 2 · Lists and checklists

        ## What to check

        - [ ] Return at the end of an item continues the list; Return on an empty item ends it
        - [ ] Tab and Shift-Tab indent and outdent an item (the keys row's ⇥ and ⇤ too)
        - [ ] Backspace at the start of an item unwinds it one step at a time
        - [ ] A tap on a box ticks it and a second tap clears it, without moving the caret
        - [ ] Numbered lists renumber when an item is added or removed
        - [ ] The bullet and box markers dim or show as Settings › Writing › Markers says

        ## Bullets

        - First
        - Second, long enough to wrap onto another line so the wrapped line lines up under the text and not under the bullet
          - Nested once
            - Nested twice
        - Back to the top

        ## Numbered

        1. One
        2. Two
        3. Three
           1. Three point one
           2. Three point two
        4. Four

        ## Checklist

        - [ ] Not done
        - [x] Done
        - [ ] A long item that wraps onto a second line, with **bold**, `code` and <span style="color:#3B82F6">colour</span> inside
          - [ ] A nested item
        - [X] Done with a capital X

        ## Mixed with other blocks

        - An item followed by code:

        ```python
        items = [1, 2, 3]
        ```

        1. A numbered item after a code block
        2. And another

        > - A list inside a quote
        > - Second item
        """#

    static let code = #"""
        # Test 3 · Code in every language

        ## What to check

        - [ ] Each block is coloured as its language, and the name button shows it
        - [ ] Run on each block prints the line in its comment (Pro), or opens the paywall (free)
        - [ ] The Run panel's Input tab feeds the input block below
        - [ ] A compile error, a runtime error and a time limit each come back with a clear message
        - [ ] Copy puts exactly the block's code on the clipboard, with a toast
        - [ ] Return keeps the indent and opens a level after {, Tab and Backspace move a level
        - [ ] Line numbers (Settings › Code) line up with every line, wrapped ones too
        - [ ] The untagged block shows as "Code" and has no Run
        - [ ] Changing a block's language from its name button retags the fence

        ## C++

        ```cpp
        #include <iostream>
        #include <vector>

        int main() {
            std::vector<int> v{3, 1, 2};
            int sum = 0;
            for (int x : v) sum += x;
            std::cout << "NoteCode OK: C++ " << sum << "\n"; // prints NoteCode OK: C++ 6
            return 0;
        }
        ```

        ## C

        ```c
        #include <stdio.h>

        int main(void) {
            printf("NoteCode OK: C %d\n", 6 * 7); // prints NoteCode OK: C 42
            return 0;
        }
        ```

        ## Java

        ```java
        public class Main {
            public static void main(String[] args) {
                System.out.println("NoteCode OK: Java"); // prints NoteCode OK: Java
            }
        }
        ```

        Java with another class name, which the run renames to Main:

        ```java
        public class Solution {
            public static void main(String[] args) {
                System.out.println("NoteCode OK: Java Solution");
            }
        }
        ```

        ## Python

        ```python
        def greet(name):
            return f"NoteCode OK: {name}"

        print(greet("Python"))  # prints NoteCode OK: Python
        ```

        ## JavaScript

        ```javascript
        const parts = ["NoteCode", "OK:", "JavaScript"];
        console.log(parts.join(" ")); // prints NoteCode OK: JavaScript
        ```

        ## Rust

        ```rust
        fn main() {
            let total: i32 = (1..=3).sum();
            println!("NoteCode OK: Rust {}", total); // prints NoteCode OK: Rust 6
        }
        ```

        ## Go

        ```go
        package main

        import "fmt"

        func main() {
            fmt.Println("NoteCode OK: Go") // prints NoteCode OK: Go
        }
        ```

        ## SQL (colours only, no Run)

        ```sql
        SELECT name, COUNT(*) AS runs
        FROM students
        WHERE course = 'CS133'
        GROUP BY name
        ORDER BY runs DESC;
        ```

        ## Tags people write

        ```py
        print("tagged py")
        ```

        ```c++
        int main() { return 0; }
        ```

        ```golang
        package main
        func main() {}
        ```

        ## Input

        Put two numbers in the Run panel's Input tab, for example 3 4:

        ```python
        a, b = map(int, input().split())
        print("sum:", a + b)
        ```

        ## Errors

        A compile error (the missing semicolon):

        ```cpp
        #include <iostream>
        int main() {
            std::cout << "never printed" << std::endl
            return 0;
        }
        ```

        A runtime error:

        ```python
        print("before")
        print(1 / 0)
        ```

        A time limit:

        ```python
        while True:
            pass
        ```

        ## Untagged and output

        ```
        An untagged block: shown as Code, with Copy and no Run.
        ```

        ```output
        NoteCode OK: an output block, on the code panel's own colours
        ```

        ## Long lines

        ```cpp
        auto aVeryLongIdentifierForWrapping = computeSomethingWithManyArguments(alpha, beta, gamma, delta, epsilon, zeta, eta, theta);
        ```

        ## A fence inside a fence

        ````
        ```
        three backticks inside four: still one block
        ```
        ````

        ## Inline code

        Inline `std::vector<int>`, `print("hi")` and `a == b` stay code, not marks.
        """#

    static let formulas = #"""
        # Test 4 · Formulas

        ## What to check

        - [ ] Every formula draws whole: nothing cut off at the top, bottom or sides
        - [ ] Tall formulas push their lines apart rather than overlapping the lines around them
        - [ ] A tap on a formula opens its editor, and its preview is never cut off
        - [ ] The broken formulas below show as red source text, not a blank
        - [ ] Formulas take the text's colour and size
        - [ ] Dollar amounts stay text
        - [ ] Formulas print whole in the PDF (Share)

        ## Inline

        Simple: $x^2 + y^2 = r^2$, $a_1, a_2, \ldots, a_n$ and $\alpha + \beta = \gamma$.

        Fractions: $\frac{a}{b}$, $\frac{n(n+1)}{2}$ and a nested one $\frac{1}{1 + \frac{1}{x}}$.

        Roots: $\sqrt{2}$, $\sqrt[3]{x + 1}$, $\sqrt{\frac{a}{b}}$.

        Big operators: $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$ and $\int_0^1 x^2 \, dx = \frac{1}{3}$.

        Complexity: $O(n \log n)$, $\Theta(n^2)$, $\Omega(1)$.

        $x$ at the start of a line, and one at its end: $y$

        ## Display in a line

        Mid-line display style: $$\sum_{k=0}^{n} \frac{n!}{k!(n-k)!} = 2^n$$ then more text after it.

        ## Display blocks

        $$ e^{i\pi} + 1 = 0 $$

        $$
        f(x) = \begin{cases} x^2 & x \geq 0 \\ -x & x < 0 \end{cases}
        $$

        $$
        \begin{pmatrix} 1 & 2 & 3 \\ 4 & 5 & 6 \\ 7 & 8 & 9 \end{pmatrix}
        \begin{pmatrix} x \\ y \\ z \end{pmatrix}
        $$

        $$
        \lim_{n \to \infty} \left( 1 + \frac{1}{n} \right)^n = e
        $$

        A very tall one:

        $$
        \frac{\frac{\frac{a}{b}}{\frac{c}{d}}}{\frac{\frac{e}{f}}{\frac{g}{h}}}
        $$

        A very wide one:

        $$
        T(n) = T\left(\frac{n}{2}\right) + T\left(\frac{n}{4}\right) + T\left(\frac{n}{8}\right) + T\left(\frac{n}{16}\right) + T\left(\frac{n}{32}\right) + O(n)
        $$

        ## In other blocks

        ### A heading with $\lambda$ in it

        - A list item with $\frac{1}{2}$
        - [ ] A checklist item with $x_i$

        > A quote with $\sqrt{x}$.

        <span style="color:#3B82F6">Blue text with $a^2$ inside</span>, and <span style="font-size:1.5em">large text with $\frac{a}{b}$</span>.

        ## Broken on purpose

        Unclosed group: $\frac{a}{b$, unknown command: $\notacommand{x}$, missing argument: $\frac{a}$.

        ## Not formulas

        It costs $5 and $10, or $5–$10. An escaped \$dollar\$ stays text.

        `$x$` in code is code. $$ unclosed display math stays text
        """#

    static let ink = #"""
        # Test 5 · Ink and the lasso

        ## What to check

        - [ ] Pen, highlighter and both erasers draw and erase where the Pencil is
        - [ ] Draw a few strokes in each box below, then lasso them
        - [ ] Drag a selection down a few rows: the page doesn't flash or redraw, and the strokes land where they were let go
        - [ ] Drag a selection out of the box and across the page break: nothing disappears
        - [ ] Tap empty space to let go of a selection: every stroke stays
        - [ ] Scale a selection from a corner, recolour it, duplicate it and delete it
        - [ ] Undo and Redo each of those, one step at a time
        - [ ] Lasso ink and text together and recolour both; code in the selection keeps its colours
        - [ ] Insert a shape, a photo and a text box, then move each
        - [ ] Leave the note, come back: every stroke is where it was left
        - [ ] Finger Draws on and off, and the Pencil's double tap or squeeze
        - [ ] Switch to text and back: the page doesn't move

        ## Box A · draw here

        Row A1 ·······················································

        Row A2 ·······················································

        Row A3 ·······················································

        Row A4 ·······················································

        ## Box B · move strokes here

        Row B1 ·······················································

        Row B2 ·······················································

        Row B3 ·······················································

        Row B4 ·······················································

        ## Text to recolour with the lasso

        Draw a loop around this sentence and a stroke beside it, then pick a colour: the words and the stroke change together.

        A second line, with **bold** and <span style="color:#2F9E44">green</span> words already in it.

        ```cpp
        // A lasso over this block must leave its colours alone.
        int main() { return 0; }
        ```

        ## Room to the page break

        Row C1

        Row C2

        Row C3

        Row C4

        Row C5

        Row C6

        Row C7

        Row C8

        Row C9

        Row C10

        Row C11

        Row C12

        Row C13

        Row C14

        Row C15

        Row C16

        Row C17

        Row C18

        Row C19

        Row C20

        ## Past the page break

        Row D1 · drag strokes from Box A down to here

        Row D2

        Row D3

        Row D4
        """#

    /// About twelve portrait pages: numbered lines, headings for the outline,
    /// code and formulas at page breaks, and one paragraph taller than a page.
    static let long: String = {
        var lines = [
            "# Test 6 · Long note",
            "",
            "## What to check",
            "",
            "- [ ] The page badge counts pages as you scroll, and the outline jumps to each section",
            "- [ ] Seamless, compressed and print layout (••• › View) break pages in the same places",
            "- [ ] Pinch to zoom: lines never re-wrap, and the page stays under your fingers",
            "- [ ] Typing near the top stays quick",
            "- [ ] Add Page adds a page at the end",
            "- [ ] Share as PDF: every page prints, with no blank page at the end",
            "- [ ] Leave the note on page 5 and come back: it reopens on page 5",
            "- [ ] Find in note (⌘F) finds \"Line 150\"",
            "",
        ]
        for line in 1...200 {
            if line % 25 == 1 {
                lines += ["## Section \(line / 25 + 1)", ""]
            }
            if line % 25 == 10 {
                lines += [
                    "```cpp",
                    "int section\(line / 25 + 1)(int n) {",
                    "    return n * \(line); // line \(line)",
                    "}",
                    "```",
                ]
            }
            if line % 25 == 18 {
                lines.append("Line \(line), with a formula: $\\sum_{i=1}^{\(line)} i = \\frac{\(line) \\cdot \(line + 1)}{2}$")
                continue
            }
            if line % 4 == 0 {
                lines.append("Line \(line): a longer paragraph that wraps across more than one line on a portrait page, so a page break can land in the middle of it and push it whole onto the next page.")
            } else {
                lines.append("Line \(line): the loop invariant holds before and after every iteration.")
            }
        }
        lines += ["", "## A paragraph taller than a page", ""]
        let sentence = "This sentence repeats so that one paragraph runs past the end of a page and has to be broken by line."
        lines.append((1...60).map { "\(sentence) (\($0))" }.joined(separator: " "))
        lines += ["", "The last line of the note."]
        return lines.joined(separator: "\n")
    }()

    static let landscape = #"""
        # Test 7 · Landscape

        ## What to check

        - [ ] The pages are landscape, and lines are as wide as the page
        - [ ] Rotating the iPad never re-wraps the text or moves the ink
        - [ ] Code, formulas and ink sit where they do in a portrait note
        - [ ] The PDF's pages are landscape too

        A paragraph long enough to show how wide a landscape line is, running on with ordinary words until it wraps at least once across the page.

        ```python
        print("NoteCode OK: landscape")
        ```

        A formula: $\frac{a + b}{c}$, and room to draw below.

        Row 1

        Row 2

        Row 3
        """#

    static let edgeCases = #"""
        # Test 8 · Edge cases

        ## What to check

        - [ ] Every line below draws, and the caret moves through it one character at a time
        - [ ] Emoji, accents and other scripts keep their shapes, and Backspace takes a whole emoji
        - [ ] The very long word and address wrap instead of running off the page
        - [ ] HTML shows as typed and nothing loads
        - [ ] Paste from Safari, Notes and Pages here: formatting arrives as Markdown
        - [ ] Copy a few lines from here into another app and back
        - [ ] The unclosed fence at the very end makes the rest a code block, and typing ``` on a line after it closes it

        ## Text

        Emoji: 😀 👩‍💻 🧑🏽‍🔬 🇰🇷 🇺🇸 ❤️ 1️⃣

        Accents: café, naïve, façade, Ångström, résumé.

        Other scripts: 한국어 텍스트, 日本語のテキスト, 中文文本, Ελληνικά, Русский.

        Right to left: مرحبا بالعالم and עברית in a line of English.

        A very long word: Pneumonoultramicroscopicsilicovolcanoconiosis_and_then_a_much_longer_identifier_with_no_spaces_at_all_to_break_it

        A very long address: https://example.com/a/very/long/path/that/keeps/going/and/going/with/no/spaces/so/it/has/to/wrap/somewhere?query=1&other=2

        Tabs:	one	two	three

        Trailing spaces after this sentence.

        ## Characters that mean something elsewhere

        <script>alert("this must stay text")</script>

        <b>HTML bold</b>, <i>HTML italic</i>, &amp; &lt; &gt;

        A backslash \ and \*escaped star\* and C:\Users\path.

        Backticks: ` alone, `` two, and ```inline triple```.

        ## Empty things

        An empty code block:

        ```
        ```

        An empty heading:

        ##

        An empty list item:

        -

        An empty checkbox:

        - [ ]

        ## The unclosed fence (keep it last)

        ```python
        print("this fence is never closed")
        """#

    static let locked = #"""
        # Test 9 · Locked text

        ## What to check

        - [ ] The text can't be edited: no keyboard, no caret, nothing pastes
        - [ ] Ink still draws over it
        - [ ] Code blocks still Copy and Run
        - [ ] ••• › Manage › Lock Text unlocks it, and the text edits again

        This note's text was locked when it was made.

        ```python
        print("NoteCode OK: locked note")
        ```
        """#

    static let nested = #"""
        # Test 11 · In a nested folder

        ## What to check

        - [ ] The folder sits inside Test Notes in the list, indented
        - [ ] Move to Folder moves this note to the top level and back
        - [ ] Drag this note onto another folder, and onto Recently Deleted
        - [ ] Restore it from Recently Deleted: it comes back to its folder
        - [ ] Search finds this note by "nested"
        - [ ] Delete the Test Notes folder: it asks what to do with what's inside
        """#
}

extension TestNotes {

    /// Makes a fresh test set: a Test Notes folder, a folder inside it, and
    /// every note, each through `Page.create` so it is a note like any other.
    /// A set already there is left alone; a second one sits beside it.
    ///
    /// - Returns: the outer folder.
    @MainActor
    @discardableResult
    static func add(to context: ModelContext, now: Date = .now) -> Folder {
        let folder = Folder(name: folderName)
        folder.colorName = FolderColor.teal.rawValue
        folder.symbolName = "ladybug"
        context.insert(folder)
        let inner = Folder(name: nestedFolderName)
        inner.colorName = FolderColor.graphite.rawValue
        context.insert(inner)
        inner.parent = folder

        // Dated a second apart, newest first, so the list sorted by date
        // shows them in their numbered order.
        for (index, note) in all.enumerated() {
            let page = Page.create(orientation: note.orientation, in: note.isNested ? inner : folder, context: context)
            page.title = note.title
            page.content = note.content
            page.isTextLocked = note.isTextLocked
            let date = now.addingTimeInterval(-Double(index))
            page.createdAt = date
            page.modifiedAt = date
        }
        return folder
    }
}
