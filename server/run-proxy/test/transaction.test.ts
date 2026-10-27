import { beforeEach, describe, expect, it } from "vitest";
import { clearTransactionCache, verifyTransaction } from "../src/transaction";
import { check, makePki, sign } from "./fixtures";

beforeEach(() => clearTransactionCache());

describe("verifyTransaction", () => {
  it("accepts a valid Pro transaction and returns its original id", async () => {
    const pki = await makePki();
    const r = await verifyTransaction(await sign(pki, {}), check(pki));
    expect(r).toEqual({ ok: true, originalTransactionId: "1000000123" });
  });

  it("refuses an expired one", async () => {
    const pki = await makePki();
    const r = await verifyTransaction(await sign(pki, { expiresDate: Date.now() - 1000 }), check(pki));
    expect(r).toEqual({ ok: false, reason: "expired" });
  });

  it("refuses another product", async () => {
    const pki = await makePki();
    const r = await verifyTransaction(await sign(pki, { productId: "tip.small" }), check(pki));
    expect(r).toEqual({ ok: false, reason: "product" });
  });

  it("refuses another app, a revoked transaction and a disallowed environment", async () => {
    const pki = await makePki();
    expect(await verifyTransaction(await sign(pki, { bundleId: "x.y" }), check(pki))).toEqual({ ok: false, reason: "bundle" });
    expect(await verifyTransaction(await sign(pki, { revocationDate: 1 }), check(pki))).toEqual({ ok: false, reason: "revoked" });
    expect(await verifyTransaction(await sign(pki, { environment: "Xcode" }), check(pki))).toEqual({ ok: false, reason: "environment" });
  });

  it("refuses a bad signature (payload swapped after signing)", async () => {
    const pki = await makePki();
    const jws = await sign(pki, {});
    const [h, , s] = jws.split(".");
    const forged = btoa(JSON.stringify({ bundleId: "com.marcus.NoteCode", productId: "test.pro.monthly", environment: "Production", originalTransactionId: "999", expiresDate: Date.now() + 1e9 }))
      .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
    expect((await verifyTransaction(`${h}.${forged}.${s}`, check(pki))).ok).toBe(false);
  });

  it("refuses a chain that does not end at a trusted root", async () => {
    const pki = await makePki();
    const other = await makePki();
    const r = await verifyTransaction(await sign(pki, {}), check(other));
    expect(r).toEqual({ ok: false, reason: "chain" });
  });

  it("refuses a signature made by a key that is not the leaf's", async () => {
    const pki = await makePki();
    const stranger = await makePki();
    const r = await verifyTransaction(await sign(pki, {}, stranger.leafKey), check(pki));
    expect(r.ok).toBe(false);
  });

  it("refuses missing and garbage input", async () => {
    const pki = await makePki();
    expect(await verifyTransaction(undefined, check(pki))).toEqual({ ok: false, reason: "missing" });
    expect(await verifyTransaction("not.a.jws", check(pki))).toEqual({ ok: false, reason: "invalid" });
  });

  it("caches a verified transaction for an hour, by the JWS", async () => {
    const pki = await makePki();
    const jws = await sign(pki, {});
    const t0 = Date.now();
    expect((await verifyTransaction(jws, check(pki), t0)).ok).toBe(true);
    // Trusted roots now wrong: only the cache can still say yes.
    expect((await verifyTransaction(jws, check(await makePki()), t0 + 1000)).ok).toBe(true);
    expect((await verifyTransaction(jws, check(await makePki()), t0 + 3_700_000)).ok).toBe(false);
  });
});
