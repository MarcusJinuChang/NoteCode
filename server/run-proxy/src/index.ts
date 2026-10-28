import { type Env, intVar } from "./env";
import { MAX_INPUT_BYTES, Judge0Unavailable, languageFor, submit, utf8Length } from "./judge0";
import { verifyTransaction, type ProCheck } from "./transaction";

export { Limits } from "./limits";
export type { Env };

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });

const fail = (status: number, error: string) => json({ error }, status);

function proCheck(env: Env, trustedRoots?: string[]): ProCheck {
  const list = (s: string) => s.split(",").map((x) => x.trim()).filter(Boolean);
  return {
    bundleId: env.BUNDLE_ID,
    productIds: list(env.PRO_PRODUCT_IDS),
    environments: list(env.ALLOWED_ENVIRONMENTS),
    trustedRoots,
  };
}

/** Exposed so tests can swap the trusted roots and the Judge0 fetch. */
export const hooks: { trustedRoots?: string[]; fetcher?: typeof fetch; now?: () => number } = {};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/run") return fail(404, "not found");
    if (request.method !== "POST") return fail(405, "method not allowed");

    // Validate the request before spending anything on it. Bodies are never logged.
    let body: Record<string, unknown>;
    try {
      const parsed = await request.json();
      if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new Error();
      body = parsed as Record<string, unknown>;
    } catch {
      return fail(400, "body must be a JSON object");
    }
    const lang = languageFor(body.language);
    if (!lang) return fail(400, "unsupported language");
    const { code } = body;
    const stdin = body.stdin ?? "";
    if (typeof code !== "string" || typeof stdin !== "string") return fail(400, "code and stdin must be strings");
    if (utf8Length(code) > MAX_INPUT_BYTES || utf8Length(stdin) > MAX_INPUT_BYTES) return fail(413, "too large");

    const now = hooks.now?.() ?? Date.now();
    const tx = await verifyTransaction(body.transaction, proCheck(env, hooks.trustedRoots), now);
    if (!tx.ok) return fail(402, "Pro required");

    const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
    const limits = env.LIMITS.get(env.LIMITS.idFromName("all")) as unknown as import("./limits").Limits;
    const hit = await limits.hit({
      subscription: tx.originalTransactionId,
      ip,
      now,
      dailyMax: intVar(env.DAILY_RUNS_PER_SUBSCRIPTION, 30),
      ipMax: intVar(env.RUNS_PER_IP_PER_MINUTE, 10),
      globalMax: intVar(env.GLOBAL_DAILY_RUNS, 1760),
    });
    if (!hit.ok) {
      return json({ limit: hit.limit, resetsAt: hit.resetsAt, runsLeft: hit.runsLeft }, 429, {
        "x-runs-left": String(hit.runsLeft),
      });
    }

    try {
      const result = await submit(env, lang, code, stdin, hooks.fetcher);
      return json(result, 200, { "x-runs-left": String(hit.runsLeft) });
    } catch (e) {
      if (e instanceof Judge0Unavailable) {
        await limits.refund(tx.originalTransactionId, ip, now);
        return fail(502, "run service unavailable");
      }
      throw e;
    }
  },
} satisfies ExportedHandler<Env>;
