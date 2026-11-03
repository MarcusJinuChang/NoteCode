//
//  CodeRunnerTests.swift
//  NoteCodeTests
//
//  The runner layer against a stubbed URLProtocol: no network.
//

import Testing
import Foundation
@testable import NoteCode

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var hang = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }
        if Self.hang { return }
        do {
            let (code, headers, data) = try Self.handler!(request)
            let r = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct CodeRunnerTests {
    static let url = URL(string: "https://run.example.test")!

    func client() -> RunServiceClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.hang = false
        return RunServiceClient(baseURL: Self.url, session: URLSession(configuration: config))
    }

    func reply(_ code: Int, _ json: String = "{}", headers: [String: String] = [:]) {
        StubProtocol.handler = { _ in (code, headers, Data(json.utf8)) }
    }

    func job(_ language: CodeLanguage = .python, code: String = "print(1)") -> RunJob {
        RunJob(language: language, code: code, stdin: "5\n", transaction: "jws.token")
    }

    // MARK: Request

    @Test func requestJSON() async throws {
        reply(200, #"{"status":"ok"}"#)
        _ = try await client().run(job(.cpp, code: "int main(){}"))
        let body = try JSONSerialization.jsonObject(with: StubProtocol.lastBody ?? Data()) as? [String: String]
        #expect(body == ["language": "c++", "code": "int main(){}", "stdin": "5\n", "transaction": "jws.token"])
    }

    @Test func requestGoesToRunPath() async throws {
        let seen = Seen()
        StubProtocol.handler = { r in
            seen.set(r)
            return (200, [:], Data(#"{"status":"ok"}"#.utf8))
        }
        _ = try await client().run(job())
        #expect(seen.request?.url?.path == "/run")
        #expect(seen.request?.httpMethod == "POST")
        #expect(seen.request?.timeoutInterval == 20)
    }

    final class Seen: @unchecked Sendable {
        var request: URLRequest?
        func set(_ r: URLRequest) { request = r }
    }

    // MARK: Statuses

    @Test func everyStatusMaps() async throws {
        let cases: [(String, RunResult.Status)] = [
            (#"{"status":"ok"}"#, .ok),
            (#"{"status":"compile_error"}"#, .compileError),
            (#"{"status":"runtime_error","exitCode":1}"#, .runtimeError(exitCode: 1, signal: nil)),
            (#"{"status":"runtime_error","signal":11}"#, .runtimeError(exitCode: nil, signal: 11)),
            (#"{"status":"time_limit"}"#, .timeLimit),
            (#"{"status":"memory_limit"}"#, .memoryLimit),
            (#"{"status":"service_error","message":"boom"}"#, .serviceError("boom")),
            (#"{"status":"something_new"}"#, .serviceError(nil)),
        ]
        for (json, expected) in cases {
            reply(200, json)
            let result = try await client().run(job())
            #expect(result.status == expected, "\(json)")
        }
    }

    @Test func fieldsAndRunsLeft() async throws {
        reply(200, #"{"status":"ok","stdout":"hi","stderr":"e","compileOutput":"c","timeSeconds":0.02,"memoryKB":3100,"truncated":true}"#,
              headers: ["X-Runs-Left": "27"])
        let r = try await client().run(job())
        #expect(r.stdout == "hi" && r.stderr == "e" && r.compileOutput == "c")
        #expect(r.timeSeconds == 0.02 && r.memoryKB == 3100 && r.truncated)
        #expect(r.runsLeft == 27)
    }

    // MARK: Errors

    @Test func httpFailuresMap() async throws {
        let cases: [(Int, RunServiceError)] = [
            (402, .notSubscribed), (413, .tooLarge),
            (500, .serviceDown), (502, .serviceDown), (503, .serviceDown), (400, .serviceDown),
        ]
        for (code, expected) in cases {
            reply(code)
            await #expect(throws: expected) { try await client().run(job()) }
        }
    }

    @Test func capCarriesScopeAndReset() async throws {
        reply(429, #"{"limit":"global","resetsAt":"2026-10-27T00:00:00Z","runsLeft":0}"#)
        let expected = RunCap(scope: .global, runsLeft: 0,
                              resetsAt: Date(timeIntervalSince1970: 1_793_059_200))
        await #expect(throws: RunServiceError.capped(expected)) { try await client().run(job()) }

        reply(429, "not json", headers: ["X-Runs-Left": "0"])
        await #expect(throws: RunServiceError.capped(RunCap(scope: .daily, runsLeft: 0, resetsAt: nil))) {
            try await client().run(job())
        }
    }

    @Test func offlineAndTimeout() async throws {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: RunServiceError.offline) { try await client().run(job()) }
        StubProtocol.handler = { _ in throw URLError(.timedOut) }
        await #expect(throws: RunServiceError.serviceDown) { try await client().run(job()) }
    }

    @Test func unreadableBodyIsServiceDown() async throws {
        reply(200, "<html>")
        await #expect(throws: RunServiceError.serviceDown) { try await client().run(job()) }
    }

    @Test func cancellation() async throws {
        let c = client()
        StubProtocol.hang = true
        let task = Task { try await c.run(job()) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: Java

    @Test func javaRenameSentAndReported() async throws {
        reply(200, #"{"status":"ok"}"#)
        let code = "public class Solution {\n  public static void main(String[] a) { System.out.println(\"Solution\"); }\n}"
        let r = try await client().run(job(.java, code: code))
        #expect(r.renamedJavaClass == "Solution")
        let body = try JSONSerialization.jsonObject(with: StubProtocol.lastBody ?? Data()) as? [String: String]
        #expect(body?["code"]?.hasPrefix("public class Main {") == true)
        #expect(body?["code"]?.contains("\"Solution\"") == true)
    }

    @Test func javaRename() {
        let code = """
        // Solution is the class
        import java.util.*;
        public class Solution {
            static Solution make() { return new Solution(); }
            /* Solution again */
            public static void main(String[] args) {
                String s = "Solution";
                char c = '"';
                String t = \"\"\"
                    Solution
                    \"\"\";
                System.out.println(s + SolutionX.v + Solution.class);
            }
        }
        class SolutionX { static int v = 1; }
        """
        let (out, renamed) = JavaMain.prepare(code)
        #expect(renamed == "Solution")
        #expect(out.contains("public class Main {"))
        #expect(out.contains("static Main make() { return new Main(); }"))
        #expect(out.contains("Main.class"))
        #expect(out.contains("// Solution is the class"))
        #expect(out.contains("/* Solution again */"))
        #expect(out.contains("String s = \"Solution\";"))
        #expect(out.contains("    Solution\n"))
        #expect(out.contains("SolutionX.v"))
        #expect(out.contains("class SolutionX"))
    }

    @Test func javaLeftAlone() {
        let main = "public class Main { public static void main(String[] a) {} }"
        #expect(JavaMain.prepare(main).renamed == nil)
        #expect(JavaMain.prepare(main).code == main)
        // No main at all: nothing to run, nothing to rename.
        #expect(JavaMain.prepare("class A { void f() {} }").renamed == nil)
        // main named only in a comment.
        #expect(JavaMain.prepare("class A { /* void main(String[] a) */ }").renamed == nil)
        // A different class is already Main: the compiler's message is better.
        let clash = "class A { public static void main(String[] a) { new Main(); } } class Main {}"
        #expect(JavaMain.prepare(clash).renamed == nil)
    }

    @Test func javaMainInNestedClass() {
        let code = "class Outer { static class Inner { public static void main(String... a) {} } }"
        // `String...` is accepted too; the innermost class holds main.
        #expect(JavaMain.prepare(code).renamed == "Inner")
    }

    // MARK: Compiler messages

    @Test func compileErrorLines() {
        func lines(_ output: String, _ l: CodeLanguage) -> [Int] {
            CompilerMessages.find(in: output, language: l).map(\.line)
        }
        #expect(lines("main.cpp:5:3: error: expected ';'", .cpp) == [5])
        #expect(lines("prog.c:12:7: error: x", .c) == [12])
        #expect(lines("Main.java:5: error: ';' expected", .java) == [5])
        #expect(lines("  File \"main.py\", line 5\n    x =\nSyntaxError", .python) == [5])
        #expect(lines("error[E0425]\n --> main.rs:5:3", .rust) == [5])
        #expect(lines("# command-line-arguments\n./main.go:5:3: undefined: x", .go) == [5])
        #expect(lines("/box/script.js:7\nthrow", .javascript) == [7])
    }

    @Test func compilerMessageDetails() {
        let out = "x\nmain.cpp:5:3: error\nmain.cpp:9: warning"
        let m = CompilerMessages.find(in: out, language: .cpp)
        #expect(m.map(\.line) == [5, 9])
        #expect(m.map(\.column) == [3, nil])
        #expect((out as NSString).substring(with: m[0].range) == "main.cpp:5:3")
        #expect(CompilerMessages.find(in: out, language: .cpp, lineCount: 6).map(\.line) == [5])
        #expect(CompilerMessages.find(in: "all fine", language: .cpp).isEmpty)
        #expect(CompilerMessages.find(in: "main.cpp:5:3", language: .sql).isEmpty)
        // Other languages' shapes don't match.
        #expect(CompilerMessages.find(in: "Main.java:5: error", language: .rust).isEmpty)
    }

    // MARK: Reads input

    @Test func readsInput() {
        let yes: [(CodeLanguage, String)] = [
            (.cpp, "int n; cin >> n;"), (.cpp, "getline(cin, s);"), (.cpp, "scanf(\"%d\", &n);"),
            (.c, "scanf(\"%d\", &n);"), (.c, "char *p = fgets(b, 9, stdin);"),
            (.java, "Scanner in = new Scanner(System.in);"),
            (.python, "n = int(input())"), (.python, "import sys\nsys.stdin.read()"),
            (.javascript, "const rl = require('readline');"), (.javascript, "process.stdin.on('data', f)"),
            (.rust, "io::stdin().read_line(&mut s)"),
            (.go, "r := bufio.NewReader(os.Stdin)"), (.go, "fmt.Scan(&n)"),
        ]
        for (l, code) in yes { #expect(ReadsInput.check(code, language: l), "\(l) \(code)") }
        let no: [(CodeLanguage, String)] = [
            (.cpp, "cout << \"hi\" << endl;"), (.cpp, "int main(){ return 0; }"),
            (.c, "printf(\"hi\");"),
            (.java, "System.out.println(1);"),
            (.python, "print('input')"), (.python, "inputs = [1]"),
            (.javascript, "console.log(1)"),
            (.rust, "println!(\"hi\");"),
            (.go, "fmt.Println(1)"),
            (.sql, "select 1;"),
        ]
        for (l, code) in no { #expect(!ReadsInput.check(code, language: l), "\(l) \(code)") }
    }
}
