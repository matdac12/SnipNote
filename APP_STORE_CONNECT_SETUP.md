# App Store Connect Product Configuration Guide

## ⚠️ Current Issue
Your products show `MISSING_METADATA` status, which means they need to be properly configured in App Store Connect before they can work in production.

## Step-by-Step Fix

### 1. Log into App Store Connect
Go to [App Store Connect](https://appstoreconnect.apple.com)

### 2. Navigate to Your App
- Select "My Apps"
- Choose "SnipNote"
- Click on "App Store" or "Prepare for Submission"

### 3. Configure In-App Purchases

#### Go to "In-App Purchases" Section
- In the left sidebar, click "In-App Purchases and Subscriptions"
- You should see your three products:
  - `snipnote_pro_weekly03`
  - `snipnote_pro_monthly03`
  - `snipnote_pro_annual03`

#### For EACH Product, Complete These Required Fields:

1. **Reference Name** (internal use only)
   - Weekly: "SnipNote Pro Weekly"
   - Monthly: "SnipNote Pro Monthly"
   - Annual: "SnipNote Pro Annual"

2. **Product ID** (should already be set)
   - Verify it matches what's in RevenueCat

3. **Subscription Duration**
   - Weekly: 1 Week
   - Monthly: 1 Month
   - Annual: 1 Year

4. **Pricing** ✅
   - Weekly: €1.99
   - Monthly: €6.99
   - Annual: €49.99
   - Select all territories or specific ones

5. **Localizations** (REQUIRED - This is likely what's missing!)
   Click "+" to add at least one localization:
   
   **For English (U.S.):**
   
   **Weekly:**
   - Display Name: "SnipNote Pro Weekly"
   - Description: "Unlock all premium features with weekly subscription"
   
   **Monthly:**
   - Display Name: "SnipNote Pro Monthly"
   - Description: "Unlock all premium features with monthly subscription - Save 33%"
   
   **Annual:**
   - Display Name: "SnipNote Pro Annual"
   - Description: "Unlock all premium features with annual subscription - Best Value!"

6. **Review Screenshot** (REQUIRED)
   - Upload a screenshot of your paywall
   - Must show the subscription UI
   - Dimensions: At least 640x920 pixels
   - Can be the same screenshot for all products

7. **Review Notes** (Optional but recommended)
   - Add: "This is a subscription for premium features in SnipNote app"
   - Test credentials if needed

### 4. Submit for Review

After completing all metadata:

1. **Save** all changes
2. Each product status should change from "Missing Metadata" to "Ready to Submit"
3. **Submit** each product for review
4. Products will be reviewed with your next app version submission

### 5. Create Subscription Group (If Not Done)

1. Go to "Subscription Groups"
2. Create a group called "SnipNote Pro" or similar
3. Add all three subscriptions to this group
4. Set the subscription ranking (Annual > Monthly > Weekly)

## Testing Before Production

### In Sandbox:
- Products will work in TestFlight and development builds
- Even with "Missing Metadata" status, they work in sandbox
- Use sandbox test accounts to verify purchases

### StoreKit Configuration File:
Your local StoreKit configuration allows testing without App Store Connect approval

## Common Issues & Solutions

**Issue: "Empty Product titles are not supported"**
- This happens when localizations are missing
- Add at least one localization per product

**Issue: Products not appearing in production**
- Products must be approved by Apple
- Submit with your next app update

**Issue: Prices not showing correctly**
- Verify price tiers in App Store Connect
- Check all territories are selected

## Verification Checklist

For each product, verify:
- [ ] Reference name is set
- [ ] Product ID matches RevenueCat
- [ ] Price is configured for your territories
- [ ] At least one localization exists
- [ ] Display name is set in localization
- [ ] Description is set in localization
- [ ] Review screenshot is uploaded
- [ ] Status shows "Ready to Submit" or "Waiting for Review"

## After Configuration

1. **In RevenueCat Dashboard:**
   - Products should show as "Active" 
   - Verify product IDs match

2. **In Your App:**
   - Force refresh the offerings
   - Products should load with proper titles and prices
   - Test purchase in sandbox mode

## Timeline

- Configuration: 10-15 minutes
- Review by Apple: 24-48 hours (with app submission)
- Production availability: After approval

## Support

- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [RevenueCat Documentation](https://www.revenuecat.com/docs/)