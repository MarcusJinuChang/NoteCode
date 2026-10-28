export interface Env {
  DAILY_RUNS_PER_SUBSCRIPTION: string;
  RUNS_PER_IP_PER_MINUTE: string;
  GLOBAL_DAILY_RUNS: string;
  PRO_PRODUCT_IDS: string;
  BUNDLE_ID: string;
  ALLOWED_ENVIRONMENTS: string;
  JUDGE0_URL: string;
  JUDGE0_HOST: string;
  /** Secret: `npx wrangler secret put JUDGE0_KEY`. Never logged, never returned. */
  JUDGE0_KEY: string;
  LIMITS: DurableObjectNamespace;
}

export function intVar(value: string | undefined, fallback: number): number {
  const n = Number.parseInt(value ?? "", 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}
