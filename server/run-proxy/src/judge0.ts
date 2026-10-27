import languages from "../languages.json";
import type { Env } from "./env";

export const MAX_INPUT_BYTES = 64 * 1024;
export const MAX_OUTPUT_BYTES = 64 * 1024;

type Entry = { id: number; name: string; compilerOptions: string };
const table = languages as unknown as Record<string, Entry>;

export function languageFor(name: unknown): Entry | undefined {
  return typeof name === "string" && Object.hasOwn(table, name) && !name.startsWith("_") ? table[name] : undefined;
}
export const supportedLanguages = () => Object.keys(table).filter((k) => !k.startsWith("_"));

export type RunStatus = "ok" | "compile_error" | "runtime_error" | "time_limit" | "memory_limit" | "service_error";

export interface RunResponse {
  status: RunStatus;
  stdout: string;
  stderr: string;
  compileOutput: string;
  timeSeconds: number | null;
  memoryKB: number | null;
  exitCode: number | null;
  signal: number | null;
  truncated: boolean;
  message: string | null;
}

export const utf8Length = (s: string) => new TextEncoder().encode(s).length;

function toBase64(s: string): string {
  let bin = "";
  for (const b of new TextEncoder().encode(s)) bin += String.fromCharCode(b);
  return btoa(bin);
}

/** Judge0 base64 (it inserts newlines) -> text, cut at `MAX_OUTPUT_BYTES`. */
export function decodeTrimmed(b64: string | null | undefined): { text: string; truncated: boolean } {
  if (!b64) return { text: "", truncated: false };
  const bin = atob(b64.replace(/\s/g, ""));
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  const truncated = bytes.length > MAX_OUTPUT_BYTES;
  return { text: new TextDecoder().decode(truncated ? bytes.slice(0, MAX_OUTPUT_BYTES) : bytes), truncated };
}

interface Judge0Submission {
  stdout?: string | null;
  stderr?: string | null;
  compile_output?: string | null;
  message?: string | null;
  time?: string | null;
  memory?: number | null;
  exit_code?: number | null;
  exit_signal?: number | null;
  status?: { id: number; description?: string };
}

export function trim(sub: Judge0Submission): RunResponse {
  const out = decodeTrimmed(sub.stdout);
  const err = decodeTrimmed(sub.stderr);
  const compile = decodeTrimmed(sub.compile_output);
  const statusId = sub.status?.id ?? 13;
  let status: RunStatus;
  let message: string | null = null;
  if (statusId === 3 || statusId === 4) status = "ok";
  else if (statusId === 5) status = "time_limit";
  else if (statusId === 6) status = "compile_error";
  else if (statusId >= 7 && statusId <= 12) status = "runtime_error";
  else {
    status = "service_error";
    message = sub.status?.description ?? "Judge0 internal error";
  }
  const time = sub.time === null || sub.time === undefined ? null : Number.parseFloat(sub.time);
  return {
    status,
    stdout: out.text,
    stderr: err.text,
    compileOutput: compile.text,
    timeSeconds: time !== null && Number.isFinite(time) ? time : null,
    memoryKB: sub.memory ?? null,
    exitCode: sub.exit_code ?? null,
    signal: sub.exit_signal ?? null,
    truncated: out.truncated || err.truncated || compile.truncated,
    message,
  };
}

export class Judge0Unavailable extends Error {}

/** One call with wait=true, so a run is billed as one submission (no polling GETs). */
export async function submit(env: Env, lang: Entry, code: string, stdin: string, fetcher: typeof fetch = fetch): Promise<RunResponse> {
  const body: Record<string, unknown> = {
    language_id: lang.id,
    source_code: toBase64(code),
    stdin: toBase64(stdin),
    cpu_time_limit: 5,
    wall_time_limit: 10,
    memory_limit: 131_072,
  };
  if (lang.compilerOptions) body.compiler_options = lang.compilerOptions;

  let res: Response;
  try {
    res = await fetcher(`${env.JUDGE0_URL}/submissions?base64_encoded=true&wait=true&fields=*`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-rapidapi-key": env.JUDGE0_KEY,
        "x-rapidapi-host": env.JUDGE0_HOST,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new Judge0Unavailable("unreachable or timed out");
  }
  if (!res.ok) throw new Judge0Unavailable(`Judge0 answered ${res.status}`);
  try {
    return trim((await res.json()) as Judge0Submission);
  } catch {
    throw new Judge0Unavailable("unreadable answer");
  }
}
