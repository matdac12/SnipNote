import { PRODUCT_MINUTES } from "./products.ts";
import type { AppleTransactionPayload } from "../_shared/apple_jws.ts";

export interface CreditHandlerDeps {
  bundleId: string;
  corsHeaders: Record<string, string>;
  authenticate: (token: string) => Promise<string | null>;
  verify: (jws: string) => Promise<AppleTransactionPayload>;
  /** Credits via credit_minutes_admin. Returns the new balance, or "conflict" when another user already holds this transaction. */
  credit: (
    args: {
      userId: string;
      amount: number;
      reason: string;
      transactionId: string;
      metadata: Record<string, unknown>;
    },
  ) => Promise<number | "conflict">;
}

export function createCreditHandler(deps: CreditHandlerDeps) {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...deps.corsHeaders, "Content-Type": "application/json" },
    });

  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: deps.corsHeaders });
    }
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    const token = (req.headers.get("Authorization") ?? "").replace(
      /^Bearer /,
      "",
    );
    const userId = token ? await deps.authenticate(token) : null;
    if (!userId) return json({ error: "Unauthorized" }, 401);

    let signedTransaction: unknown;
    try {
      ({ signedTransaction } = await req.json());
    } catch {
      return json({ error: "Invalid body" }, 400);
    }
    if (typeof signedTransaction !== "string" || !signedTransaction) {
      return json({ error: "signedTransaction is required" }, 400);
    }

    let tx: AppleTransactionPayload;
    try {
      tx = await deps.verify(signedTransaction);
    } catch (error) {
      console.error(
        "Transaction verification failed:",
        (error as Error).message,
      );
      return json({ error: "Transaction could not be verified" }, 403);
    }

    if (tx.bundleId !== deps.bundleId) {
      return json({ error: "Wrong bundle" }, 403);
    }
    if (tx.revocationDate) {
      return json({ error: "Transaction was revoked" }, 403);
    }
    const product = PRODUCT_MINUTES[tx.productId];
    if (!product) return json({ error: "Unknown product" }, 422);

    const result = await deps.credit({
      userId,
      amount: product.minutes,
      reason: product.reason,
      transactionId: String(tx.transactionId),
      metadata: {
        source: "storekit_verified",
        product_id: tx.productId,
        environment: tx.environment,
        original_transaction_id: tx.originalTransactionId,
      },
    });
    if (result === "conflict") {
      return json({ error: "Transaction belongs to another account" }, 409);
    }
    return json({ balance: result, credited: product.minutes });
  };
}
