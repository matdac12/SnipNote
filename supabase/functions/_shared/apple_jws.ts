import { X509Certificate } from "@peculiar/x509";
import { compactVerify, decodeProtectedHeader, importX509 } from "jose";

export interface AppleTransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  environment: string;
  signedDate: number;
  purchaseDate: number;
  expiresDate?: number;
  revocationDate?: number;
  [key: string]: unknown;
}

// Marker extensions Apple puts on the StoreKit signing chain.
const LEAF_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

function fromBase64(b64: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/**
 * Verifies a StoreKit 2 signed transaction (JWS) offline: ES256 signature by the leaf, leaf signed
 * by the intermediate, intermediate signed by the pinned Apple root. Returns the verified payload.
 * Certificate validity is checked at the payload's signedDate so old unfinished transactions still verify.
 */
export async function verifyAppleTransaction(
  jws: string,
  options: { rootCertDER: Uint8Array<ArrayBuffer> },
): Promise<AppleTransactionPayload> {
  const header = decodeProtectedHeader(jws);
  if (
    header.alg !== "ES256" || !Array.isArray(header.x5c) ||
    header.x5c.length < 2
  ) {
    throw new Error("Unsupported JWS header");
  }

  const leaf = new X509Certificate(fromBase64(header.x5c[0]));
  const intermediate = new X509Certificate(fromBase64(header.x5c[1]));
  const root = new X509Certificate(options.rootCertDER);

  if (
    !leaf.getExtension(LEAF_OID) || !intermediate.getExtension(INTERMEDIATE_OID)
  ) {
    throw new Error("Certificate chain is missing Apple marker extensions");
  }
  if (
    !(await leaf.verify({
      publicKey: intermediate.publicKey,
      signatureOnly: true,
    }))
  ) {
    throw new Error("Leaf certificate is not signed by the intermediate");
  }
  if (
    !(await intermediate.verify({
      publicKey: root.publicKey,
      signatureOnly: true,
    }))
  ) {
    throw new Error("Intermediate certificate is not signed by the Apple root");
  }

  const key = await importX509(leaf.toString("pem"), "ES256");
  const { payload } = await compactVerify(jws, key);
  const decoded = JSON.parse(
    new TextDecoder().decode(payload),
  ) as AppleTransactionPayload;

  const at = new Date(decoded.signedDate);
  for (const cert of [leaf, intermediate, root]) {
    if (at < cert.notBefore || at > cert.notAfter) {
      throw new Error(
        "Certificate was not valid when the transaction was signed",
      );
    }
  }
  return decoded;
}
