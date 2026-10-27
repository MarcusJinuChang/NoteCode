import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";

export type LimitName = "daily" | "ip" | "global";

export interface HitRequest {
  subscription: string;
  ip: string;
  /** Epoch milliseconds; passed in so tests control the clock. */
  now: number;
  dailyMax: number;
  ipMax: number;
  globalMax: number;
}

export type HitResult =
  | { ok: true; runsLeft: number }
  | { ok: false; limit: LimitName; resetsAt: string; runsLeft: number };

const DAY = 86_400_000;
const MINUTE = 60_000;

export const dayKey = (now: number) => new Date(now).toISOString().slice(0, 10);
export const nextMidnight = (now: number) => new Date((Math.floor(now / DAY) + 1) * DAY).toISOString();
export const nextMinute = (now: number) => new Date((Math.floor(now / MINUTE) + 1) * MINUTE).toISOString();

/**
 * One instance holds every counter, so the three checks and the increment are
 * atomic (a Durable Object runs one request at a time; KV would let a burst
 * through). Stores only the day's counts: subscription ids (opaque numbers),
 * IPs for the current minute. A new day or minute drops the old keys.
 */
export class Limits extends DurableObject<Env> {
  async hit(req: HitRequest): Promise<HitResult> {
    const day = dayKey(req.now);
    const minute = Math.floor(req.now / MINUTE);
    await this.rollOver(day, minute);

    const subKey = `s:${req.subscription}`;
    const ipKey = `i:${req.ip}`;
    const got = await this.ctx.storage.get<number>(["global", subKey, ipKey]);
    const global = got.get("global") ?? 0;
    const sub = got.get(subKey) ?? 0;
    const ip = got.get(ipKey) ?? 0;
    const runsLeft = Math.max(0, req.dailyMax - sub);

    if (sub >= req.dailyMax) {
      return { ok: false, limit: "daily", resetsAt: nextMidnight(req.now), runsLeft: 0 };
    }
    if (ip >= req.ipMax) {
      return { ok: false, limit: "ip", resetsAt: nextMinute(req.now), runsLeft };
    }
    if (global >= req.globalMax) {
      return { ok: false, limit: "global", resetsAt: nextMidnight(req.now), runsLeft };
    }
    await this.ctx.storage.put({ global: global + 1, [subKey]: sub + 1, [ipKey]: ip + 1 });
    return { ok: true, runsLeft: req.dailyMax - (sub + 1) };
  }

  /** Gives a run back when Judge0 failed, so the service's fault isn't the student's run. */
  async refund(subscription: string, ip: string, now: number): Promise<void> {
    if ((await this.ctx.storage.get<string>("day")) !== dayKey(now)) return;
    const keys = ["global", `s:${subscription}`, `i:${ip}`];
    const got = await this.ctx.storage.get<number>(keys);
    const next: Record<string, number> = {};
    for (const k of keys) {
      const v = got.get(k);
      if (v !== undefined && v > 0) next[k] = v - 1;
    }
    await this.ctx.storage.put(next);
  }

  private async rollOver(day: string, minute: number) {
    const storedDay = await this.ctx.storage.get<string>("day");
    if (storedDay !== day) {
      await this.ctx.storage.deleteAll();
      await this.ctx.storage.put({ day, minute });
      return;
    }
    const storedMinute = await this.ctx.storage.get<number>("minute");
    if (storedMinute !== minute) {
      const old = await this.ctx.storage.list({ prefix: "i:" });
      await this.ctx.storage.delete([...old.keys()]);
      await this.ctx.storage.put("minute", minute);
    }
  }
}
