# Minutes-Based Pricing System - Edge Cases & Fixes
**Date:** September 23, 2025
**System:** SnipNote Minutes-Based Pricing
**Status:** Analysis Complete, Implementation Pending

---

## 🔍 Executive Summary

After comprehensive analysis of the minutes-based pricing system implementation, several critical edge cases have been identified that could impact user experience, revenue integrity, and system reliability. This document outlines each issue with its potential impact and recommended solution.

---

## 🚨 Critical Issues (Must Fix Before Production)

### 1. **Duplicate Transaction Credits**

**Current State:**
- StoreKit's `Transaction.updates` listener can fire multiple times for the same transaction
- No mechanism to track which transaction IDs have already been processed
- Minutes are credited every time `handleMinutesForTransaction()` is called

**Risk Level:** ⚠️ **HIGH**

**Potential Impact:**
- User purchases 500-minute pack once
- Due to network retry or app restart, transaction processes 3 times
- User receives 1,500 minutes instead of 500
- **Revenue Loss:** $4.99 worth of product yields $14.97 worth of credits

**Evidence in Code:**
```swift
// StoreManager.swift - No duplicate check
private func handleMinutesForTransaction(_ transaction: Transaction, product: Product) async {
    let transactionID = String(transaction.id)
    // ISSUE: No check if this transactionID was already processed
    let success = await MinutesManager.shared.creditForPack(product, transactionID: transactionID)
}
```

**Recommended Fix:**
- Maintain a local Set of processed transaction IDs in UserDefaults
- Check before crediting: `if processedTransactions.contains(transactionID) { return }`
- Add to set only after successful credit
- Consider server-side idempotency as backup

---

### 2. **Race Condition: Debit After Transcription**

**Current State:**
- Minutes are debited AFTER transcription completes
- If user has 1 minute and starts 90-second recording, check passes
- Transcription happens first, then debit attempts
- If debit fails (network error), user got free transcription

**Risk Level:** ⚠️ **HIGH**

**Potential Impact:**
- Users can exploit by going offline after transcription starts
- No way to "rollback" a completed transcription
- Potential for unlimited free usage with network manipulation

**Evidence in Code:**
```swift
// CreateMeetingView.swift - Line 1032-1037
let transcript = try await openAIService.transcribeAudioFromURL(...)
// ISSUE: Transcription happens FIRST

// Only THEN do we debit
if let meetingId = createdMeetingId {
    _ = await minutesManager.debitMinutes(seconds: duration, meetingID: meetingId.uuidString)
}
```

**Recommended Fix:**
- Implement "reservation" pattern:
  1. Reserve required minutes before transcription
  2. Perform transcription
  3. Convert reservation to actual debit
  4. Release reservation if cancelled/failed

---

### 3. **Negative Balance Exploitation**

**Current State:**
- System allows negative balance with no limit
- Comment says "Allow negative balance temporarily" but no enforcement
- User could go -1000 minutes and keep using the app

**Risk Level:** ⚠️ **HIGH**

**Potential Impact:**
- User with 0 minutes starts recording
- Goes negative indefinitely
- No mechanism to force payment or limit usage

**Evidence in Code:**
```swift
// MinutesManager.swift - Line 135
currentBalance = newBalance // Allow negative balance temporarily
// ISSUE: No limit on how negative it can go
```

**Recommended Fix:**
- Track `hasUsedGracePeriod` flag per user
- Limit negative balance to -5 minutes maximum
- Block new recordings if balance < -5
- Force purchase prompt when negative

---

### 4. **No Offline Queue for Failed Operations**

**Current State:**
- If network fails during debit, operation is lost
- No retry mechanism
- No queue for pending operations

**Risk Level:** 🟡 **MEDIUM**

**Potential Impact:**
- Legitimate debits lost due to network issues
- Revenue leakage over time
- Inconsistent balance between device and server

**Recommended Fix:**
- Implement operation queue with persistence
- Retry failed debits with exponential backoff
- Process queue on app launch and network restoration

---

## 🟡 Medium Priority Issues

### 5. **Stale Balance Display**

**Current State:**
- Balance only refreshes on specific actions
- No automatic refresh on app foreground
- Could show outdated balance if user purchased on another device

**Evidence:**
- `refreshBalance()` only called in `onAppear` of certain views
- No observer for app entering foreground

**Recommended Fix:**
```swift
// Add to MinutesManager
private func setupBackgroundObserver() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(refreshOnForeground),
        name: UIApplication.willEnterForegroundNotification,
        object: nil
    )
}
```

---

### 6. **Concurrent Device Usage**

**Current State:**
- No handling for same account on multiple devices
- Both devices could start recording simultaneously
- Race condition on who debits first

**Risk Level:** 🟡 **MEDIUM**

**Potential Impact:**
- User with 10 minutes starts recording on iPhone and iPad
- Both check balance (10 minutes) and allow recording
- Both debit 10 minutes
- User ends with -10 balance instead of 0

**Recommended Fix:**
- Implement optimistic locking with version numbers
- Real-time balance sync via Supabase subscriptions
- Show "Recording on another device" warning

---

## 🟢 Low Priority Improvements

### 7. **Unclear Rounding Communication**

**Current State:**
- User-friendly rounding (119s = 1min, 120s = 2min) not clearly communicated
- Users might be confused why 61-second recording costs 2 minutes

**Recommended Fix:**
- Add tooltip/info button explaining rounding
- Show "~2 minutes will be used" during recording
- Add explanation in Settings

---

### 8. **Missing Transaction History**

**Current State:**
- No way for users to see their minutes transaction history
- Can't verify credits/debits
- No audit trail for support

**Recommended Fix:**
- Add "Minutes History" section in Settings
- Show last 30 days of transactions
- Include: date, type (credit/debit), amount, balance after

---

## 📋 Implementation Priority Matrix

| Priority | Issue | User Impact | Revenue Impact | Dev Effort |
|----------|-------|-------------|----------------|------------|
| 🔴 P0 | Duplicate Credits | Low | HIGH | Low |
| 🔴 P0 | Debit Timing | Medium | HIGH | Medium |
| 🔴 P0 | Negative Balance | Medium | HIGH | Low |
| 🟡 P1 | Offline Queue | Medium | Medium | Medium |
| 🟡 P1 | Stale Balance | High | Low | Low |
| 🟡 P2 | Concurrent Devices | Low | Medium | High |
| 🟢 P3 | Rounding Display | Medium | Low | Low |
| 🟢 P3 | Transaction History | Low | Low | Medium |

---

## 🛠 Recommended Implementation Order

### Phase 1: Critical Fixes (1-2 days)
1. Add transaction duplicate prevention
2. Fix debit timing (reserve → transcribe → debit)
3. Limit negative balance

### Phase 2: Reliability (2-3 days)
4. Implement offline queue
5. Add balance refresh on foreground
6. Add retry logic for failed operations

### Phase 3: Polish (1-2 days)
7. Improve UI messaging about rounding
8. Add transaction history view
9. Handle concurrent device usage

---

## 🧪 Testing Checklist

### Transaction Integrity
- [ ] Purchase same pack twice rapidly → Should only credit once
- [ ] Force-quit app during purchase → Should credit on next launch
- [ ] Airplane mode after transcription starts → Should handle gracefully

### Balance Accuracy
- [ ] Start recording with 1 minute, record for 90 seconds
- [ ] Go negative, try to start new recording
- [ ] Purchase pack while negative → Should add to negative balance

### Network Resilience
- [ ] Toggle airplane mode during various operations
- [ ] Weak network simulation
- [ ] Server timeout scenarios

### Multi-Device
- [ ] Same account on 2 devices simultaneously
- [ ] Purchase on device A, check balance on device B
- [ ] Start recording on both devices with limited minutes

---

## 💡 Additional Considerations

### Server-Side Validations Needed
1. Enforce idempotency on `credit_minutes` RPC using `apple_transaction_id`
2. Add rate limiting to prevent rapid debit attempts
3. Implement transaction log for audit trail
4. Add webhook for Apple's server-to-server notifications

### Analytics to Add
- Track failed debit attempts
- Monitor negative balance frequency
- Alert on duplicate transaction attempts
- Dashboard for minutes usage patterns

### Future Enhancements
- "Low balance" push notification at 5 minutes
- Auto-purchase option when balance hits 0
- Bulk minute packages for enterprise
- Minutes sharing between family members

---

## 📊 Risk Assessment

**If shipped without fixes:**
- **Revenue Risk:** Up to 30% potential revenue loss from exploits
- **User Trust:** Negative experience from balance inconsistencies
- **Support Load:** Increased tickets about missing/extra minutes
- **Churn Risk:** Users frustrated by unclear limits may abandon

**With all P0 fixes:**
- Revenue protection achieved
- Core functionality reliable
- Acceptable for production launch

---

## ✅ Sign-off Checklist

Before production release:
- [ ] All P0 issues resolved
- [ ] Server-side idempotency implemented
- [ ] Comprehensive testing completed
- [ ] Support team briefed on new system
- [ ] Rollback plan prepared
- [ ] Monitoring dashboards configured

---

**Document prepared by:** Claude
**Last updated:** September 23, 2025
**Next review:** Before production deployment