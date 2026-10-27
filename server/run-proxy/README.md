# NoteCode run proxy

A Cloudflare Worker between the app and hosted Judge0 CE (RapidAPI). It holds
the Judge0 key, checks the caller is a Pro subscriber, limits runs, and returns
a trimmed result. The app knows our language names only, never a Judge0 id or
key. The contract the app codes against is
[docs/design/run-proxy-contract.md](../../docs/design/run-proxy-contract.md);
change both together.

## Contract (short)

`POST /run` with `{ "language", "code", "stdin", "transaction" }`:

- `language`: `c++ c java python javascript rust go` (anything else, `sql`
  included, is 400). `code` and `stdin`: UTF-8, 64KB each (413 over).
- `transaction`: the StoreKit 2 signed transaction (JWS). It is verified
  against Apple's chain (pinned to Apple Root CA - G3), the bundle id, a Pro
  product id, an allowed environment, not revoked and not expired. Otherwise **402**.
- **200** with `X-Runs-Left`: `{ status, stdout, stderr, compileOutput,
  timeSeconds, memoryKB, exitCode, signal, truncated, message }`. Each output
  is cut at 64KB. `status`: `ok`, `compile_error`, `runtime_error`,
  `time_limit`, `service_error` (Judge0 reports no memory-limit status, so
  `memory_limit` is never sent today).
- **429** `{ limit: "daily" | "ip" | "global", resetsAt, runsLeft }`.
- **502** when Judge0 is unreachable, slow or answers nonsense (the app reads
  it as `serviceDown`); that run is not counted against the student.

Limits (`wrangler.toml` `[vars]`, no code change): 30 runs a day per
subscription (by original transaction id, so a reinstall doesn't reset it),
10 a minute per IP, 1,760 a day for everyone (≈ $3). Counters live in one
Durable Object (atomic, unlike KV) and only for the current UTC day/minute.
Request bodies are never logged.

## Before the first deploy

Two things in `wrangler.toml` are Marcus's:

1. `PRO_PRODUCT_IDS` is a placeholder. Put the subscription's product id from
   P1 / App Store Connect there, or every run is refused with 402.
2. `languages.json` has the Judge0 ids, pinned on 26 Oct 2026 from
   <https://ce.judge0.com/languages>. Judge0 has no "latest" alias, so check
   them when you upgrade. The hosted RapidAPI instance should match CE, but
   confirm with one run per language after deploying (and that each run is
   billed once).

## Deploy (Marcus)

```sh
cd server/run-proxy && npm install
npx wrangler secret put JUDGE0_KEY   # paste the RapidAPI key when asked
npx wrangler deploy
```

Then set `AppInfo.runService` in `AppSettings.swift` to the printed
`https://notecode-run-proxy.<account>.workers.dev` URL.

## Tests

```sh
npm test        # vitest in the Workers runtime; no network, Judge0 is stubbed
npm run typecheck
```

Transactions in the tests are signed by a throwaway chain generated per test;
the real roots are only in `src/transaction.ts`.
