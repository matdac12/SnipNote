// Minutes credited per StoreKit product. Server-side source of truth: the client never sends an amount.
// Keep in sync with MinutesManager.getMinutesForProduct in the iOS app.
export const PRODUCT_MINUTES: Record<
  string,
  { minutes: number; reason: string }
> = {
  snipnote_pro_weekly03: { minutes: 200, reason: "weekly_allowance" },
  snipnote_pro_monthly03: { minutes: 800, reason: "monthly_allowance" },
  snipnote_pro_annual03: { minutes: 9600, reason: "annual_allowance" },
  "com.snipnote.packs.minutes100": { minutes: 100, reason: "pack_100" },
  "com.snipnote.packs.minutes500": { minutes: 500, reason: "pack_500" },
  "com.snipnote.packs.minutes1000": { minutes: 1000, reason: "pack_1000" },
};
