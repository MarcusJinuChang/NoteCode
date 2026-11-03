//
//  Perf.swift
//  NoteCodeTests
//
//  One line per cost test, `PERF <test> <seconds>`, which scripts/perf.sh
//  collects from the test log and sets against docs/refactor/baseline.md.
//  A cost test calls this beside its `#expect`; the bounds stay as they are.
//

import Foundation

/// Prints the number `scripts/perf.sh` reads. `name` is `Suite/test`, with
/// a suffix where one test reports more than one number.
func reportPerf(_ name: String, seconds: TimeInterval) {
    print("PERF \(name) \(String(format: "%.4f", seconds))")
}
