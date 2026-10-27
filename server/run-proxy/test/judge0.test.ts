import { describe, expect, it } from "vitest";
import languages from "../languages.json";
import { decodeTrimmed, languageFor, supportedLanguages, trim } from "../src/judge0";

const b64 = (s: string) => btoa(s);

describe("language table", () => {
  it("has exactly the contract's languages with their pinned Judge0 ids", () => {
    const ids = Object.fromEntries(supportedLanguages().map((k) => [k, languageFor(k)!.id]));
    expect(ids).toEqual({ "c++": 105, c: 103, java: 91, python: 109, javascript: 102, rust: 108, go: 107 });
  });
  it("refuses sql, unknown names and prototype keys", () => {
    for (const n of ["sql", "cobol", "constructor", "_comment", "", 5, null]) expect(languageFor(n)).toBeUndefined();
  });
  it("names each compiler so a wrong id is visible in review", () => {
    expect(languages["c++"].name).toContain("C++");
    expect(languages.java.name).toContain("Java");
  });
});

describe("trim", () => {
  it("maps Judge0 statuses", () => {
    const status = (id: number) => trim({ status: { id } }).status;
    expect(status(3)).toBe("ok");
    expect(status(5)).toBe("time_limit");
    expect(status(6)).toBe("compile_error");
    for (const id of [7, 8, 9, 10, 11, 12]) expect(status(id)).toBe("runtime_error");
    expect(status(13)).toBe("service_error");
    expect(status(14)).toBe("service_error");
  });
  it("carries output, exit code, signal, time and memory", () => {
    const r = trim({ status: { id: 11 }, stdout: b64("hi\n"), stderr: b64("boom"), exit_code: 1, exit_signal: null, time: "0.02", memory: 3100 });
    expect(r).toMatchObject({ status: "runtime_error", stdout: "hi\n", stderr: "boom", exitCode: 1, signal: null, timeSeconds: 0.02, memoryKB: 3100, truncated: false, message: null });
  });
  it("cuts each output at 64KB and says so", () => {
    const big = b64("a".repeat(70_000));
    const r = trim({ status: { id: 3 }, stdout: big });
    expect(r.stdout.length).toBe(65_536);
    expect(r.truncated).toBe(true);
  });
  it("reads Judge0's wrapped base64", () => {
    expect(decodeTrimmed("aGk=\n").text).toBe("hi");
  });
  it("explains an internal error", () => {
    expect(trim({ status: { id: 13, description: "Internal Error" } }).message).toBe("Internal Error");
  });
});
