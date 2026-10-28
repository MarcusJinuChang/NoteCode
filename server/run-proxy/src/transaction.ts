import { X509Certificate } from "@peculiar/x509";
import { compactVerify, decodeProtectedHeader, importX509 } from "jose";

/** SHA-256 of Apple Root CA - G3's DER, which signs StoreKit 2's chain. */
export const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

export interface ProCheck {
  bundleId: string;
  productIds: string[];
  environments: string[];
  /** Fingerprints (lowercase hex SHA-256) of roots we trust. Tests pass their own. */
  trustedRoots?: string[];
}

export type Verified = { ok: true; originalTransactionId: string } | { ok: false; reason: string };

const CACHE_MS = 3_600_000;
const cache = new Map<string, { originalTransactionId: string; until: number }>();

export function clearTransactionCache() {
  cache.clear();
}

const hex = (buf: ArrayBuffer) =>
  [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

async function chainIsTrusted(x5c: string[], now: number, roots: string[]): Promise<X509Certificate | null> {
  if (x5c.length < 2) return null;
  const ders = x5c.map(base64ToBytes);
  const certs = ders.map((d) => new X509Certificate(d));
  const rootFingerprint = hex(await crypto.subtle.digest("SHA-256", ders[ders.length - 1]));
  if (!roots.includes(rootFingerprint)) return null;
  const when = new Date(now);
  for (let i = 0; i < certs.length; i++) {
    if (when < certs[i].notBefore || when > certs[i].notAfter) return null;
    if (i + 1 < certs.length) {
      const signedByParent = await certs[i].verify({ publicKey: certs[i + 1].publicKey, signatureOnly: true });
      if (!signedByParent) return null;
    }
  }
  return certs[0];
}

/**
 * Verifies a StoreKit 2 signed transaction: signature, Apple's chain to the
 * pinned root, bundle, product, environment, not revoked, not expired. Cached
 * for an hour by the JWS itself (the original transaction id comes from the
 * payload, so a cache keyed on it would trust an unverified claim).
 */
export async function verifyTransaction(jws: unknown, check: ProCheck, now = Date.now()): Promise<Verified> {
  if (typeof jws !== "string" || jws.length === 0 || jws.length > 16_384) {
    return { ok: false, reason: "missing" };
  }
  const hit = cache.get(jws);
  if (hit && hit.until > now) return { ok: true, originalTransactionId: hit.originalTransactionId };

  try {
    const header = decodeProtectedHeader(jws);
    if (header.alg !== "ES256" || !Array.isArray(header.x5c)) return { ok: false, reason: "header" };
    const leaf = await chainIsTrusted(header.x5c as string[], now, check.trustedRoots ?? [APPLE_ROOT_CA_G3_SHA256]);
    if (!leaf) return { ok: false, reason: "chain" };

    const key = await importX509(leaf.toString("pem"), "ES256");
    const { payload } = await compactVerify(jws, key);
    const tx = JSON.parse(new TextDecoder().decode(payload)) as Record<string, unknown>;

    if (tx.bundleId !== check.bundleId) return { ok: false, reason: "bundle" };
    if (typeof tx.productId !== "string" || !check.productIds.includes(tx.productId)) {
      return { ok: false, reason: "product" };
    }
    if (typeof tx.environment !== "string" || !check.environments.includes(tx.environment)) {
      return { ok: false, reason: "environment" };
    }
    if (tx.revocationDate !== undefined && tx.revocationDate !== null) return { ok: false, reason: "revoked" };
    if (typeof tx.expiresDate !== "number" || tx.expiresDate <= now) return { ok: false, reason: "expired" };
    const id = tx.originalTransactionId;
    if (typeof id !== "string" && typeof id !== "number") return { ok: false, reason: "id" };

    const originalTransactionId = String(id);
    cache.set(jws, { originalTransactionId, until: Math.min(now + CACHE_MS, tx.expiresDate) });
    return { ok: true, originalTransactionId };
  } catch {
    return { ok: false, reason: "invalid" };
  }
}
