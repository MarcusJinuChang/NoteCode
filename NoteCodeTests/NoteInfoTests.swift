//
//  NoteInfoTests.swift
//  NoteCodeTests
//

import Testing
@testable import NoteCode

@Suite("Note info")
struct NoteInfoTests {

    @Test("An empty note has no words and no code")
    func empty() {
        let info = NoteInfo(content: "")

        #expect(info.words == 0)
        #expect(info.code.isEmpty)
        #expect(info.codeBlocks == 0)
    }

    @Test("Words are the prose's, without the markdown around them")
    func words() {
        let note = """
        # Lecture on Pointers
        A pointer **holds** an *address*.
        - first item
        1. second item

        Use `ptr` carefully.
        """

        // 3 + 5 + 2 + 2 + 3: the #, the list markers and the ** and `
        // around words aren't words.
        #expect(NoteInfo(content: note).words == 15)
    }

    @Test("Code isn't counted as words")
    func codeIsNotWords() {
        let note = "Two words\n```cpp\nint main() { return 0; }\n```\n"

        #expect(NoteInfo(content: note).words == 2)
    }

    @Test("Code blocks are grouped by language, in the hotbar's order")
    func codeByLanguage() {
        let note = """
        ```python
        print("a")
        ```
        ```c++
        int x;
        int y;
        ```
        ```rust
        fn main() {}
        ```
        ```cpp
        x++;
        ```
        ```
        plain
        ```
        """

        let info = NoteInfo(content: note)

        // c++ and cpp are one language; rust, unknown to the app, and a
        // fence with no language both count as Other.
        #expect(info.code.map(\.language) == [.cpp, .python, nil])
        #expect(info.code.map(\.name) == ["C++", "Python", "Other"])
        #expect(info.code.map(\.blocks) == [2, 1, 2])
        #expect(info.code.map(\.lines) == [3, 1, 2])
        #expect(info.codeBlocks == 5)
        #expect(info.words == 0)
    }

    @Test("Blank lines count, and so does an unclosed block's last line")
    func lineCounting() {
        let note = "```java\nclass A {\n\n}\n```\n```python\nx = 1\ny = 2"

        let info = NoteInfo(content: note)

        #expect(info.code.map(\.language) == [.java, .python])
        #expect(info.code.map(\.lines) == [3, 2])
    }

    @Test("An empty block is a block with no lines")
    func emptyBlock() {
        let info = NoteInfo(content: "```cpp\n```")

        #expect(info.code.map(\.blocks) == [1])
        #expect(info.code.map(\.lines) == [0])
    }

    @Test("A Windows line ending is one line break")
    func crlf() {
        let info = NoteInfo(content: "one two\r\nthree\r\n```cpp\r\na\r\nb\r\n```")

        #expect(info.words == 3)
        #expect(info.code.map(\.lines) == [2])
    }

    @Test("Languages have the names people write")
    func displayNames() {
        #expect(CodeLanguage.allCases.map(\.displayName) == ["C++", "Java", "Python"])
    }
}
