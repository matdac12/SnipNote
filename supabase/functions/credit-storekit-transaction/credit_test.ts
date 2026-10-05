import * as x509 from "@peculiar/x509";
import { CompactSign } from "jose";
import { verifyAppleTransaction } from "../_shared/apple_jws.ts";
import { createCreditHandler } from "./handler.ts";

x509.cryptoProvider.set(crypto);
const alg = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" };

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

async function makeChain(opts: { leafOid?: boolean } = {}) {
  const gen = () =>
    crypto.subtle.generateKey(alg, true, ["sign", "verify"]) as Promise<
      CryptoKeyPair
    >;
  const [rootK, interK, leafK] = [await gen(), await gen(), await gen()];
  const marker = (oid: string) =>
    new x509.Extension(oid, false, new Uint8Array([5, 0]));
  const notBefore = new Date("2020-01-01");
  const notAfter = new Date("2040-01-01");
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: "CN=Test Root",
    notBefore,
    notAfter,
    signingAlgorithm: alg,
    keys: rootK,
  });
  const inter = await x509.X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test Inter",
    issuer: root.subject,
    notBefore,
    notAfter,
    signingAlgorithm: alg,
    publicKey: interK.publicKey,
    signingKey: rootK.privateKey,
    extensions: [marker("1.2.840.113635.100.6.2.1")],
  });
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03",
    subject: "CN=Test Leaf",
    issuer: inter.subject,
    notBefore,
    notAfter,
    signingAlgorithm: alg,
    publicKey: leafK.publicKey,
    signingKey: interK.privateKey,
    extensions: opts.leafOid === false
      ? []
      : [marker("1.2.840.113635.100.6.11.1")],
  });
  return { root, inter, leaf, leafKey: leafK.privateKey };
}

const b64 = (c: x509.X509Certificate) =>
  btoa(String.fromCharCode(...new Uint8Array(c.rawData)));

async function sign(
  chain: Awaited<ReturnType<typeof makeChain>>,
  payload: Record<string, unknown>,
) {
  return await new CompactSign(
    new TextEncoder().encode(JSON.stringify(payload)),
  )
    .setProtectedHeader({
      alg: "ES256",
      x5c: [b64(chain.leaf), b64(chain.inter), b64(chain.root)],
    })
    .sign(chain.leafKey);
}

const payload = {
  transactionId: "2000000111",
  originalTransactionId: "1000000111",
  bundleId: "com.mattianalytics.snipnote",
  productId: "com.snipnote.packs.minutes100",
  environment: "Production",
  signedDate: Date.now(),
  purchaseDate: Date.now(),
};

Deno.test("accepts a transaction signed by a chain that reaches the pinned root", async () => {
  const chain = await makeChain();
  const tx = await verifyAppleTransaction(await sign(chain, payload), {
    rootCertDER: new Uint8Array(chain.root.rawData),
  });
  assert(tx.productId === payload.productId, "payload not returned");
});

Deno.test("rejects a chain that does not reach the pinned root", async () => {
  const chain = await makeChain();
  const other = await makeChain();
  let threw = false;
  try {
    await verifyAppleTransaction(await sign(chain, payload), {
      rootCertDER: new Uint8Array(other.root.rawData),
    });
  } catch {
    threw = true;
  }
  assert(threw, "should reject foreign root");
});

Deno.test("rejects a leaf without the Apple marker extension", async () => {
  const chain = await makeChain({ leafOid: false });
  let threw = false;
  try {
    await verifyAppleTransaction(await sign(chain, payload), {
      rootCertDER: new Uint8Array(chain.root.rawData),
    });
  } catch {
    threw = true;
  }
  assert(threw, "should reject missing marker");
});

Deno.test("rejects a tampered payload", async () => {
  const chain = await makeChain();
  const jws = await sign(chain, payload);
  const [h, , s] = jws.split(".");
  const forged = btoa(
    JSON.stringify({ ...payload, productId: "com.snipnote.packs.minutes1000" }),
  )
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
  let threw = false;
  try {
    await verifyAppleTransaction(`${h}.${forged}.${s}`, {
      rootCertDER: new Uint8Array(chain.root.rawData),
    });
  } catch {
    threw = true;
  }
  assert(threw, "should reject tampering");
});

Deno.test("rejects an unsigned/self-made JSON body", async () => {
  let threw = false;
  try {
    await verifyAppleTransaction("not-a-jws", {
      rootCertDER: new Uint8Array(1),
    });
  } catch {
    threw = true;
  }
  assert(threw, "should reject garbage");
});

function handlerFixture(
  opts: {
    tx?: Record<string, unknown>;
    verifyFails?: boolean;
    credit?: number | "conflict";
  } = {},
) {
  const credits: unknown[] = [];
  const handler = createCreditHandler({
    bundleId: "com.mattianalytics.snipnote",
    corsHeaders: {},
    authenticate: (t) => Promise.resolve(t === "good" ? "user-1" : null),
    verify: () =>
      opts.verifyFails
        ? Promise.reject(new Error("bad"))
        : Promise.resolve({ ...payload, ...opts.tx } as never),
    credit: (args) => {
      credits.push(args);
      return Promise.resolve(opts.credit ?? 100);
    },
  });
  const call = (token: string | null, body: unknown) =>
    handler(
      new Request("http://x", {
        method: "POST",
        headers: token ? { Authorization: `Bearer ${token}` } : {},
        body: JSON.stringify(body),
      }),
    );
  return { call, credits };
}

Deno.test("handler: unauthenticated is rejected and nothing is credited", async () => {
  const f = handlerFixture();
  assert(
    (await f.call(null, { signedTransaction: "x" })).status === 401,
    "expected 401",
  );
  assert(f.credits.length === 0, "credited");
});

Deno.test("handler: credits the server-side amount for the verified product, ignoring client amounts", async () => {
  const f = handlerFixture();
  const res = await f.call("good", { signedTransaction: "x", amount: 999999 });
  assert(res.status === 200, "expected 200");
  const c = f.credits[0] as {
    amount: number;
    userId: string;
    transactionId: string;
  };
  assert(
    c.amount === 100 && c.userId === "user-1" &&
      c.transactionId === "2000000111",
    "wrong credit",
  );
});

Deno.test("handler: failed verification, wrong bundle, revoked and unknown product credit nothing", async () => {
  for (
    const [f, status] of [
      [handlerFixture({ verifyFails: true }), 403],
      [handlerFixture({ tx: { bundleId: "other.app" } }), 403],
      [handlerFixture({ tx: { revocationDate: 1 } }), 403],
      [handlerFixture({ tx: { productId: "nope" } }), 422],
    ] as const
  ) {
    assert(
      (await f.call("good", { signedTransaction: "x" })).status === status,
      `expected ${status}`,
    );
    assert(f.credits.length === 0, "credited");
  }
});

Deno.test("handler: transaction held by another account returns 409", async () => {
  const f = handlerFixture({ credit: "conflict" });
  assert(
    (await f.call("good", { signedTransaction: "x" })).status === 409,
    "expected 409",
  );
});
