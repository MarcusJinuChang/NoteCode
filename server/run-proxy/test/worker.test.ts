import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import worker, { hooks, type Env } from "../src/index";
import { clearTransactionCache } from "../src/transaction";
import { makePki, sign, PRO, BUNDLE, type Pki } from "./fixtures";

const KEY = "SECRET-JUDGE0-KEY-123";
let pki: Pki;
let calls: { url: string; body: any; headers: Headers }[];
let upstream: () => Response;

function testEnv(over: Partial<Record<keyof Env, string>> = {}): Env {
  return {
    ...(env as unknown as Env),
    DAILY_RUNS_PER_SUBSCRIPTION: "3",
    RUNS_PER_IP_PER_MINUTE: "100",
    GLOBAL_DAILY_RUNS: "100",
    PRO_PRODUCT_IDS: PRO,
    BUNDLE_ID: BUNDLE,
    ALLOWED_ENVIRONMENTS: "Production,Sandbox",
    JUDGE0_URL: "https://judge0.test",
    JUDGE0_HOST: "judge0.test",
    JUDGE0_KEY: KEY,
    ...over,
  } as Env;
}

const ok = () =>
  new Response(JSON.stringify({ status: { id: 3 }, stdout: btoa("hello\n"), time: "0.01", memory: 100, exit_code: 0 }));

async function run(over: Record<string, unknown> = {}, e = testEnv(), ip = "1.1.1.1", id = "tx-default") {
  const transaction = await sign(pki, { originalTransactionId: id });
  const req = new Request("https://proxy.test/run", {
    method: "POST",
    headers: { "cf-connecting-ip": ip },
    body: JSON.stringify({ language: "python", code: "print('hello')", stdin: "", transaction, ...over }),
  });
  return worker.fetch(req, e);
}

beforeEach(async () => {
  clearTransactionCache();
  pki = await makePki();
  calls = [];
  upstream = ok;
  hooks.trustedRoots = [pki.rootFingerprint];
  hooks.now = undefined;
  hooks.fetcher = (async (url: string, init: RequestInit) => {
    calls.push({ url, body: JSON.parse(init.body as string), headers: new Headers(init.headers) });
    return upstream();
  }) as typeof fetch;
});

describe("validation", () => {
  it("400 for an unknown language, sql and a non-JSON body", async () => {
    expect((await run({ language: "cobol" })).status).toBe(400);
    expect((await run({ language: "sql" })).status).toBe(400);
    const bad = await worker.fetch(new Request("https://proxy.test/run", { method: "POST", body: "nope" }), testEnv());
    expect(bad.status).toBe(400);
    expect(calls).toHaveLength(0);
  });
  it("400 when code is not a string", async () => {
    expect((await run({ code: 5 })).status).toBe(400);
  });
  it("413 over 64KB of code or of stdin, by bytes not characters", async () => {
    expect((await run({ code: "a".repeat(65_537) })).status).toBe(413);
    expect((await run({ stdin: "a".repeat(65_537) })).status).toBe(413);
    expect((await run({ code: "é".repeat(33_000) })).status).toBe(413);
    expect((await run({ code: "a".repeat(65_536) })).status).toBe(200);
  });
  it("404 and 405 elsewhere", async () => {
    expect((await worker.fetch(new Request("https://proxy.test/other", { method: "POST" }), testEnv())).status).toBe(404);
    expect((await worker.fetch(new Request("https://proxy.test/run"), testEnv())).status).toBe(405);
  });
});

describe("Pro only", () => {
  it("402 without a transaction, with a bad one, and with an expired one; Judge0 never called", async () => {
    expect((await run({ transaction: undefined })).status).toBe(402);
    expect((await run({ transaction: "x.y.z" })).status).toBe(402);
    expect((await run({ transaction: await sign(pki, { expiresDate: 1 }) })).status).toBe(402);
    expect(calls).toHaveLength(0);
  });
});

describe("a run", () => {
  it("forwards to Judge0 once with the pinned id and returns the trimmed result", async () => {
    const res = await run({ language: "c++", code: "int main(){}", stdin: "5" });
    expect(res.status).toBe(200);
    expect(res.headers.get("x-runs-left")).toBe("2");
    expect(await res.json()).toMatchObject({ status: "ok", stdout: "hello\n", exitCode: 0, truncated: false });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toContain("base64_encoded=true&wait=true");
    expect(calls[0].body).toMatchObject({
      language_id: 105,
      compiler_options: "-std=c++17",
      cpu_time_limit: 5,
      wall_time_limit: 10,
      memory_limit: 131072,
      source_code: btoa("int main(){}"),
      stdin: btoa("5"),
    });
  });
  it("never shows the key in a response, success or failure", async () => {
    const good = await (await run()).text();
    upstream = () => new Response(`bad ${KEY}`, { status: 500 });
    const bad = await run();
    const text = good + (await bad.text()) + [...bad.headers].join();
    expect(text).not.toContain(KEY);
    expect(calls[1].headers.get("x-rapidapi-key")).toBe(KEY);
  });
});

describe("Judge0 trouble", () => {
  it("maps a 5xx, a network failure and nonsense to 502, and gives the run back", async () => {
    upstream = () => new Response("x", { status: 503 });
    expect((await run({}, testEnv(), "2.2.2.2", "tx-a")).status).toBe(502);
    hooks.fetcher = (async () => { throw new TypeError("network"); }) as typeof fetch;
    expect((await run({}, testEnv(), "2.2.2.2", "tx-a")).status).toBe(502);
    hooks.fetcher = (async () => new Response("<html>")) as typeof fetch;
    expect((await run({}, testEnv(), "2.2.2.2", "tx-a")).status).toBe(502);
    // All three were refunded: the full three runs are still there.
    upstream = ok;
    hooks.fetcher = (async () => upstream()) as typeof fetch;
    for (let i = 0; i < 3; i++) expect((await run({}, testEnv(), "2.2.2.2", "tx-a")).status).toBe(200);
  });
  it("passes Judge0's own failures through as status service_error", async () => {
    upstream = () => new Response(JSON.stringify({ status: { id: 13, description: "Internal Error" } }));
    const body: any = await (await run({}, testEnv(), "3.3.3.3", "tx-b")).json();
    expect(body).toMatchObject({ status: "service_error", message: "Internal Error" });
  });
});

describe("limits", () => {
  it("daily: the fourth run of a subscription gets 429 with limit, resetsAt and runsLeft 0", async () => {
    for (let i = 0; i < 3; i++) expect((await run({}, testEnv(), "4.4.4.4", "tx-d")).status).toBe(200);
    const res = await run({}, testEnv(), "4.4.4.4", "tx-d");
    expect(res.status).toBe(429);
    const body: any = await res.json();
    expect(body).toMatchObject({ limit: "daily", runsLeft: 0 });
    expect(Date.parse(body.resetsAt)).toBeGreaterThan(Date.now());
    expect(res.headers.get("x-runs-left")).toBe("0");
    expect(calls).toHaveLength(3);
  });
  it("daily counts follow the original transaction id, not the IP", async () => {
    for (let i = 0; i < 3; i++) await run({}, testEnv(), `5.5.5.${i}`, "tx-e");
    expect((await run({}, testEnv(), "5.5.5.9", "tx-e")).status).toBe(429);
    expect((await run({}, testEnv(), "5.5.5.9", "tx-f")).status).toBe(200);
  });
  it("ip: per minute, and resets with the minute", async () => {
    const e = testEnv({ RUNS_PER_IP_PER_MINUTE: "2" });
    const t0 = Math.floor(Date.now() / 60_000) * 60_000 + 1000;
    hooks.now = () => t0;
    expect((await run({}, e, "6.6.6.6", "tx-g1")).status).toBe(200);
    expect((await run({}, e, "6.6.6.6", "tx-g2")).status).toBe(200);
    const res = await run({}, e, "6.6.6.6", "tx-g3");
    expect(res.status).toBe(429);
    expect(await res.json()).toMatchObject({ limit: "ip" });
    hooks.now = () => t0 + 60_000;
    expect((await run({}, e, "6.6.6.6", "tx-g3")).status).toBe(200);
  });
  it("global: the ceiling stops everyone, and says so", async () => {
    const e = testEnv({ GLOBAL_DAILY_RUNS: "2" });
    expect((await run({}, e, "7.7.7.1", "tx-h1")).status).toBe(200);
    expect((await run({}, e, "7.7.7.2", "tx-h2")).status).toBe(200);
    const res = await run({}, e, "7.7.7.3", "tx-h3");
    expect(res.status).toBe(429);
    expect(await res.json()).toMatchObject({ limit: "global" });
  });
  it("a refused run is not counted", async () => {
    await run({ transaction: "bad" }, testEnv(), "8.8.8.8", "tx-i");
    for (let i = 0; i < 3; i++) expect((await run({}, testEnv(), "8.8.8.8", "tx-i")).status).toBe(200);
  });
});
