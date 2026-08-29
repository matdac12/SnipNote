# SnipNote Minutes Model — Subscriptions (Capped) + Consumable Packs
_Last updated: 2025-09-22 08:40 UTC_


**Currency:** EUR (€)  •  **Apple fee:** 30%  •  **Whisper cost:** €0.006/min

## Overview
- **Free tier**: **30 minutes total** (one-time allowance for new users)
- **Weekly subscription**: €TBD → **200 minutes/week** allowance
- **Monthly subscription (existing)**: €6.99 → **800 minutes/month** allowance
- **Annual subscription (existing)**: €49.99 → **9,600 minutes/year** allowance
- **Consumable packs** (non‑renewing): **100**, **500**, and **1,000** minutes
- **Rollover**: On subscription renewal, allowance **adds to remaining balance** (does not reset)
- **Purchase entry points**: Show **pack purchase UI** when minutes run out and **from Settings** at any time
- **Rounding policy**: User-friendly - **round down to current minute** (119 seconds = 1 minute, 120 seconds = 2 minutes)
- **Insufficient minutes warnings**: If a user imports or records a longer audio than remaining minutes, **warn before processing**
- **Negative balance**: Allow completion of current recording, then require top-up before next recording

---

## Product IDs (App Store Connect)
Use stable, explicit identifiers:

```text
com.snipnote.sub.weekly              # 200 minutes/week
com.snipnote.sub.monthly             # 800 minutes/month
com.snipnote.sub.annual              # 9,600 minutes/year
com.snipnote.packs.minutes100        # 100 minutes pack
com.snipnote.packs.minutes500        # 500 minutes pack
com.snipnote.packs.minutes1000       # 1,000 minutes pack
```

---

## Pricing math & recommendations (packs)
Let **P** be the list price. After Apple’s 30% fee you get **0.7 × P**. Whisper cost is **€0.006/min**.

| Pack | Cost (Whisper) | Break‑even Price (P_min = cost/0.7) | Recommended Price | Your Net (≈ 70%) | Gross Margin vs Cost |
|---|---:|---:|---:|---:|---:|
| 100 min | €0.60 | **€0.86** | **€1.49** | €1.04 | **€0.44** |
| 500 min | €3.00 | **€4.29** | **€4.99** | €3.49 | **€0.49** |
| 1,000 min | €6.00 | **€8.59** | **€9.99** | €6.99 | **€0.99** |

> These give a **small positive margin** and keep subscription attractive on a per‑minute basis.

---

## App Store Connect — Steps
1. **Subscriptions (no price change)**
   - Monthly: set marketing text → “Includes **800 minutes/month**. Minutes roll over. Buy extra packs anytime.”
   - Annual: set marketing text → “Includes **9,600 minutes/year**. Minutes roll over. Buy extra packs anytime.”
   - Weekly: leave as‑is for now.

2. **Create consumables**
   - **100 Minutes Pack** → `com.snipnote.packs.minutes100` → Price €1.49 → Description "Adds 100 minutes to your balance."
   - **500 Minutes Pack** → `com.snipnote.packs.minutes500` → Price €4.99 → Description "Adds 500 minutes to your balance."
   - **1,000 Minutes Pack** → `com.snipnote.packs.minutes1000` → Price €9.99 → Description "Adds 1,000 minutes to your balance."

3. **(Later) App Store Server Notifications v2**
   - Defer for now. We’ll credit minutes client‑side on verified transactions and add ASN in a future version.

---

## Data model (Supabase already exists)
You already track user minutes and costs. Keep Supabase as **source of truth**. Codex/MCP will wire endpoints; this doc specifies **expected behaviors** only.

### Required backend behaviors (high‑level)
- **Fetch balance**: return current `balance_minutes` for the authenticated user.
- **Credit**: add minutes with reasons:
  - `free_tier` (+30, one-time for new users)
  - `weekly_allowance` (+200)
  - `monthly_allowance` (+800)
  - `annual_allowance` (+9600)
  - `pack_100` (+100)
  - `pack_500` (+500)
  - `pack_1000` (+1000)
- **Debit**: subtract minutes (rounded‑up usage). Never go below 0.
- **Idempotency**: ensure the same Apple transaction is credited **once**.
- **Auth**: secure per‑user rows (RLS). Client reads/writes only the current user’s balance.

> MCP/Codex will implement concrete RPCs or REST endpoints. No server changes are required for this doc beyond enforcing the above contract.

---

## Client (SwiftUI + StoreKit 2) — Implementation

### 1) Load products
```swift
import StoreKit

enum ProductID: String, CaseIterable {
    case weekly = "com.snipnote.sub.weekly"
    case monthly = "com.snipnote.sub.monthly"
    case annual = "com.snipnote.sub.annual"
    case pack100 = "com.snipnote.packs.minutes100"
    case pack500 = "com.snipnote.packs.minutes500"
    case pack1000 = "com.snipnote.packs.minutes1000"
}

struct AppProducts {
    let weekly: Product
    let monthly: Product
    let annual: Product
    let pack100: Product
    let pack500: Product
    let pack1000: Product

    static func load() async throws -> AppProducts {
        let ids = ProductID.allCases.map(\.rawValue)
        let prods = try await Product.products(for: ids)

        func get(_ id: ProductID) -> Product {
            guard let p = prods.first(where: { $0.id == id.rawValue }) else {
                fatalError("Missing product: \(id.rawValue)")
            }
            return p
        }
        return .init(
            weekly: get(.weekly),
            monthly: get(.monthly),
            annual: get(.annual),
            pack100: get(.pack100),
            pack500: get(.pack500),
            pack1000: get(.pack1000)
        )
    }
}
```

### 2) Purchase + verification + credit
```swift
import StoreKit

@MainActor
final class BillingManager: ObservableObject {
    @Published var products: AppProducts?
    @Published var isPurchasing = false

    func load() async {
        do { products = try await AppProducts.load() } catch { print("Load error:", error) }
    }

    func purchase(_ product: Product) async throws {
        isPurchasing = true; defer { isPurchasing = false }
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let tx = try checkVerified(verification)
            await tx.finish()

            // Map product → minutes delta
            let (delta, reason): (Int, String) = {
                switch tx.productID {
                case ProductID.weekly.rawValue:   return (200,  "weekly_allowance")
                case ProductID.monthly.rawValue:  return (800,  "monthly_allowance")
                case ProductID.annual.rawValue:   return (9600, "annual_allowance")
                case ProductID.pack100.rawValue:  return (100,  "pack_100")
                case ProductID.pack500.rawValue:  return (500,  "pack_500")
                case ProductID.pack1000.rawValue: return (1000, "pack_1000")
                default: return (0, "unknown")
                }
            }()

            if delta > 0 {
                // Tell Supabase to credit minutes (idempotent by transactionID on server side)
                try await MinutesAPI.shared.creditMinutes(delta: delta,
                                                          reason: reason,
                                                          appleTransactionID: String(tx.id))
                await MinutesStore.shared.refresh()
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe): return safe
        }
    }

    /// Call on app start
    func listenForUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                do {
                    let tx = try self?.checkVerified(update)
                    if let t = tx {
                        await t.finish()
                        // Same mapping & creditMinutes as in purchase()
                        // Ensure server idempotency on transactionID
                    }
                } catch {
                    print("Verification failed:", error)
                }
            }
        }
    }
}
```

### 3) Minutes API shim (client → Supabase)
> **Note:** Endpoints are placeholders. Codex/MCP will bind to your actual Supabase RPC/REST with authenticated user context and idempotency.

```swift
import Foundation

struct MinutesAPI {
    static let shared = MinutesAPI()
    private init() {}

    func fetchBalance() async throws -> Int {
        // GET /minutes/balance → { "balance": Int }
        // Replace with your Supabase client call or RPC
        return try await SupabaseBridge.fetchBalance()
    }

    func creditMinutes(delta: Int, reason: String, appleTransactionID: String) async throws {
        // POST /minutes/credit → { delta, reason, txid }
        try await SupabaseBridge.credit(delta: delta, reason: reason, txid: appleTransactionID)
    }

    func debitMinutes(minutes: Int, meetingID: String?) async throws -> Int {
        // POST /minutes/debit → { minutes, meetingID? } → returns new balance
        return try await SupabaseBridge.debit(minutes: minutes, meetingID: meetingID)
    }
}
```

### 4) Minutes store + usage debit
```swift
import Foundation

@MainActor
final class MinutesStore: ObservableObject {
    static let shared = MinutesStore()
    @Published private(set) var balance: Int = 0

    private init() {}

    func refresh() async {
        do { balance = max(0, try await MinutesAPI.shared.fetchBalance()) }
        catch { print("Balance fetch failed:", error) }
    }

    /// Round seconds using user-friendly rounding for billing
    func debitForAudio(seconds: Int, meetingID: String?) async throws {
        let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
        let newBal = try await MinutesAPI.shared.debitMinutes(minutes: minutes, meetingID: meetingID)
        self.balance = max(0, newBal)
    }
}
```

### 5) Warnings for insufficient minutes
#### Import flow (example)
```swift
func willExceedBalance(importDurationSec: Int, currentBalanceMin: Int) -> Bool {
    let needed = Int(ceil(Double(importDurationSec)/60.0))
    return needed > currentBalanceMin
}
```

- If `willExceedBalance(...) == true`:
  - Show alert: “This import needs **{needed} minutes**, you have **{balance}** left.”
  - Buttons: **Buy Pack** (show 500/1000) • **Cancel**.

#### Live recording flow
- As recording passes `balance_minutes * 60` seconds, show a **non‑blocking banner**:  
  “You’re about to exceed your remaining minutes. Buy a pack to continue analysis after recording.”

### 6) UI — Paywall and Settings
- **Keep paywall as‑is** (subscriptions cards).
- **Settings**: show **Remaining Minutes** (large number) + two buttons:
  - “Buy 500 Minutes” → purchase `pack500`
  - “Buy 1,000 Minutes” → purchase `pack1000`
- **Empty state** (balance == 0): surface inline CTA in Create New Meeting:
  - “You’re out of minutes. Get the Monthly (800 min) or buy a pack.”

---

## Testing (StoreKit Test)
- Use StoreKit Test with a configuration where a month is compressed (e.g., 5 minutes) to simulate renewals.
- Cases to verify:
  1. Purchase monthly → balance **+800**.
  2. Purchase annual → balance **+9600**.
  3. Purchase packs → **+500** / **+1000** immediately.
  4. Debit rounding: 61s → **2 minutes** debited.
  5. Warning appears when importing audio needing more minutes than remaining.
  6. Rollover: on renewal, **+800** added to remaining balance.
  7. Transaction updates processed once; repeat updates don’t double‑credit (server idempotency).

---

## Release Notes (copy snippet)
“SnipNote now uses a **minutes allowance**: Monthly includes **800 minutes** and Annual **9,600 minutes**. Minutes **roll over**. Need more? Buy **500** or **1,000** minute packs from Settings. Clear, fair, and predictable.”

---

## Security & Policies (brief)
- Enforce **RLS** so users can only read/write their own balance and ledger entries.
- Require idempotency keys or store processed **Apple transaction IDs** server‑side.
- Do not start paid processing if balance is 0; always **warn & block** until purchase is complete.
- Add telemetry for: purchases, credits applied, debits, and low‑minutes warnings.

---

## Roadmap (later)
- Add **App Store Server Notifications v2** for renewals/refunds to credit minutes server‑side without client involvement.
- Offer a **2,000‑minute pack** if demand warrants.
- Consider removing the weekly tier after adoption data on packs.
