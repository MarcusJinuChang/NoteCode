//
//  RunServiceClient.swift
//  NoteCode
//
//  Talks to our run proxy (docs/design/run-proxy-contract.md). The app never
//  sees a Judge0 id or key; the proxy owns both.
//

import Foundation

nonisolated protocol CodeRunning: Sendable {
    /// Runs the job. Cancelling the calling task cancels the request and
    /// throws `CancellationError`. Failures are `RunServiceError`.
    func run(_ job: RunJob) async throws -> RunResult
}

nonisolated struct RunServiceClient: CodeRunning {
    var baseURL: URL
    var session: URLSession
    var timeout: TimeInterval

    init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func run(_ job: RunJob) async throws -> RunResult {
        var code = job.code
        var renamed: String?
        if job.language == .java {
            (code, renamed) = JavaMain.prepare(code)
        }
        var request = URLRequest(url: baseURL.appending(path: "run"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.body(job, code: code)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw RunServiceError.serviceDown }

        let runsLeft = http.value(forHTTPHeaderField: "X-Runs-Left").flatMap { Int($0) }
        switch http.statusCode {
        case 200:
            guard var result = Self.decodeResult(data) else { throw RunServiceError.serviceDown }
            result.runsLeft = runsLeft
            result.renamedJavaClass = renamed
            return result
        case 402: throw RunServiceError.notSubscribed
        case 413: throw RunServiceError.tooLarge
        case 429: throw RunServiceError.capped(Self.decodeCap(data, runsLeft: runsLeft))
        default:  throw RunServiceError.serviceDown
        }
    }

    // MARK: Wire format

    static func body(_ job: RunJob, code: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Request(language: job.language.canonicalName, code: code,
                                          stdin: job.stdin, transaction: job.transaction))
    }

    private struct Request: Encodable {
        var language: String
        var code: String
        var stdin: String
        var transaction: String
    }

    private struct Response: Decodable {
        var status: String
        var stdout: String?
        var stderr: String?
        var compileOutput: String?
        var timeSeconds: Double?
        var memoryKB: Int?
        var exitCode: Int?
        var signal: Int?
        var truncated: Bool?
        var message: String?
    }

    static func decodeResult(_ data: Data) -> RunResult? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let status: RunResult.Status
        switch r.status {
        case "ok":             status = .ok
        case "compile_error":  status = .compileError
        case "runtime_error":  status = .runtimeError(exitCode: r.exitCode, signal: r.signal)
        case "time_limit":     status = .timeLimit
        case "memory_limit":   status = .memoryLimit
        case "service_error":  status = .serviceError(r.message)
        default:               status = .serviceError(r.message)
        }
        return RunResult(status: status, stdout: r.stdout ?? "", stderr: r.stderr ?? "",
                         compileOutput: r.compileOutput ?? "", timeSeconds: r.timeSeconds,
                         memoryKB: r.memoryKB, truncated: r.truncated ?? false)
    }

    private struct CapBody: Decodable {
        var limit: String?
        var resetsAt: String?
        var runsLeft: Int?
    }

    static func decodeCap(_ data: Data, runsLeft header: Int?) -> RunCap {
        let body = try? JSONDecoder().decode(CapBody.self, from: data)
        let scope: RunCap.Scope = switch body?.limit {
        case "ip":     .perMinute
        case "global": .global
        default:       .daily
        }
        var date: Date?
        if let s = body?.resetsAt {
            date = (try? Date(s, strategy: .iso8601))
                ?? (try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return RunCap(scope: scope, runsLeft: body?.runsLeft ?? header, resetsAt: date)
    }

    private static func map(_ error: URLError) -> any Error {
        switch error.code {
        case .cancelled:
            return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotFindHost, .cannotConnectToHost, .internationalRoamingOff:
            return RunServiceError.offline
        default:
            return RunServiceError.serviceDown
        }
    }
}
