import * as x509 from "@peculiar/x509";
import { CompactSign } from "jose";

const alg = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" } as const;
const b64 = (buf: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const hex = (buf: ArrayBuffer) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

export const BUNDLE = "com.marcus.NoteCode";
export const PRO = "test.pro.monthly";

export interface Pki {
  /** x5c entries, leaf first. */
  chain: string[];
  leafKey: CryptoKey;
  rootFingerprint: string;
}

async function cert(subject: string, issuer: string, publicKey: CryptoKey, signingKey: CryptoKey, serial: string, ca: boolean) {
  const now = Date.now();
  return x509.X509CertificateGenerator.create({
    serialNumber: serial,
    subject: `CN=${subject}`,
    issuer: `CN=${issuer}`,
    notBefore: new Date(now - 86_400_000),
    notAfter: new Date(now + 86_400_000 * 365),
    signingAlgorithm: alg,
    publicKey,
    signingKey,
    extensions: [new x509.BasicConstraintsExtension(ca, undefined, true)],
  });
}

/** A root -> intermediate -> leaf chain of our own, standing in for Apple's. */
export async function makePki(): Promise<Pki> {
  const root = (await crypto.subtle.generateKey(alg, true, ["sign", "verify"])) as CryptoKeyPair;
  const mid = (await crypto.subtle.generateKey(alg, true, ["sign", "verify"])) as CryptoKeyPair;
  const leaf = (await crypto.subtle.generateKey(alg, true, ["sign", "verify"])) as CryptoKeyPair;
  const rootCert = await cert("Test Root", "Test Root", root.publicKey, root.privateKey, "01", true);
  const midCert = await cert("Test Mid", "Test Root", mid.publicKey, root.privateKey, "02", true);
  const leafCert = await cert("Test Leaf", "Test Mid", leaf.publicKey, mid.privateKey, "03", false);
  return {
    chain: [leafCert, midCert, rootCert].map((c) => b64(c.rawData)),
    leafKey: leaf.privateKey,
    rootFingerprint: hex(await crypto.subtle.digest("SHA-256", rootCert.rawData)),
  };
}

export async function sign(pki: Pki, claims: Record<string, unknown>, key: CryptoKey = pki.leafKey): Promise<string> {
  const payload = {
    bundleId: BUNDLE,
    productId: PRO,
    environment: "Production",
    originalTransactionId: "1000000123",
    expiresDate: Date.now() + 86_400_000,
    ...claims,
  };
  return new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
    .setProtectedHeader({ alg: "ES256", x5c: pki.chain })
    .sign(key);
}

export const check = (pki: Pki) => ({
  bundleId: BUNDLE,
  productIds: [PRO],
  environments: ["Production", "Sandbox"],
  trustedRoots: [pki.rootFingerprint],
});
