import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { corsHeaders } from "../_shared/cors.ts";
import { verifyAppleTransaction } from "../_shared/apple_jws.ts";
import { APPLE_ROOT_CA_G3_BASE64 } from "../_shared/apple_root.ts";
import { createCreditHandler } from "./handler.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { autoRefreshToken: false, persistSession: false } },
);
const rootCertDER = Uint8Array.from(
  atob(APPLE_ROOT_CA_G3_BASE64),
  (c) => c.charCodeAt(0),
);

Deno.serve(createCreditHandler({
  bundleId: "com.mattianalytics.snipnote",
  corsHeaders,
  authenticate: async (token) => {
    const { data, error } = await admin.auth.getUser(token);
    return error || !data.user ? null : data.user.id;
  },
  verify: (jws) => verifyAppleTransaction(jws, { rootCertDER }),
  credit: async ({ userId, amount, reason, transactionId, metadata }) => {
    const { data, error } = await admin.rpc("credit_minutes_admin", {
      p_user_id: userId,
      p_amount: amount,
      p_reason: reason,
      p_apple_transaction_id: transactionId,
      p_metadata: metadata,
    });
    if (error) {
      // Unique index on apple_transaction_id: the transaction is already credited to a different user.
      if (error.code === "23505") return "conflict";
      throw new Error(error.message);
    }
    return data as number;
  },
}));
