# The run proxy's contract

What the app's runner (`RunServiceClient`, R1) sends and expects from the
proxy (`server/run-proxy/`, R2). R2 must follow this; change both together.
The app knows our language names only, never a Judge0 id or key.

## Request

`POST {AppInfo.runService}/run`, `Content-Type: application/json`:

```json
{ "language": "c++", "code": "…", "stdin": "…", "transaction": "<JWS>" }
```

- `language` is `CodeLanguage.canonicalName`: `c++`, `java`, `python`, `c`,
  `javascript`, `rust`, `go`. Anything else (including `sql`) gets 400.
- `code` and `stdin` are plain UTF-8 strings (the proxy does the base64 for
  Judge0). `stdin` may be empty. Each is limited to 64KB.
- `transaction` is the subscription's StoreKit 2 signed transaction. The limits
  key on its original transaction id; there is no install id.
- Java arrives with the class holding `main` already renamed to `Main`.

## Responses

**200**, with `X-Runs-Left: <n>` (the subscription's runs left today):

```json
{
  "status": "ok",
  "stdout": "", "stderr": "", "compileOutput": "",
  "timeSeconds": 0.02, "memoryKB": 3100,
  "exitCode": 0, "signal": null,
  "truncated": false, "message": null
}
```

`status` is one of `ok`, `compile_error`, `runtime_error` (with `exitCode`
and/or `signal`), `time_limit`, `memory_limit`, `service_error` (Judge0
internal failure; `message` says what). An unknown value is read as
`service_error`. Output strings are capped at 64KB each, `truncated` is true
if any was cut. Absent fields read as empty/nil.

**Failures** (the app maps them to `RunServiceError`):

| Status | Meaning | App error |
|---|---|---|
| 402 | transaction missing, invalid, expired or not Pro | `notSubscribed` |
| 413 | code or stdin over 64KB | `tooLarge` |
| 429 | a limit was hit | `capped` |
| other 4xx, 5xx, unreadable body | | `serviceDown` |

A 429 body: `{ "limit": "daily" | "ip" | "global", "resetsAt": "<ISO 8601>",
"runsLeft": 0 }`. `limit` says which limit (`daily` per subscription, `ip`
per minute, `global` ceiling for the day); `resetsAt` when it lifts. All
fields are optional to the app; a missing `limit` reads as `daily`.

The app times out after 20 seconds, which is longer than the proxy's wall
limit (10s) plus Judge0's overhead, so a timeout means the service is down.
No network at all is `offline` in the app, never seen by the proxy.
