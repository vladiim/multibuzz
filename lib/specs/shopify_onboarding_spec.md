# Shopify Onboarding & Documentation Spec

**Status**: In Progress
**Created**: 2025-12-18
**Updated**: 2025-12-18
**Priority**: High (blocking UAT completion)

---

## Progress Summary

### Completed (2025-12-18)
- [x] Email-based visitor lookup fallback in webhook handler (for "Buy it now" flows)
- [x] Theme extension updated to store visitor_id in localStorage (checkout pixel can access)
- [x] Custom pixel code created with checkout_started, add_to_cart, checkout events
- [x] Pixel reads visitor_id from localStorage instead of cookies
- [x] Theme extension deployed (v3)
- [x] Identity creation working via pixel (verified in production)

### Blocking Issues
- [ ] **Webhook not configured**: Need to create `orders/paid` webhook in Shopify admin pointing to `https://mbuzz.co/webhooks/shopify`
- [ ] **End-to-end test**: Full purchase flow not yet verified (blocked by webhook)

### Next Session
1. Configure webhook in Shopify admin (Settings → Notifications → Webhooks)
2. Test full purchase flow with webhook
3. Build dashboard settings UI for Shopify configuration

---

## Problem

Currently, configuring Shopify integration requires manual Rails console updates:
```ruby
account.update(shopify_domain: "store.myshopify.com", shopify_webhook_secret: "secret")
```

This is unacceptable for self-service onboarding.

---

## Solution

### 1. Dashboard Settings UI

Add Shopify configuration to the account settings page.

**Location**: `/dashboard/settings` or new `/dashboard/integrations` page

**Fields**:
| Field | Type | Validation | Example |
|-------|------|------------|---------|
| Shopify Domain | text | Must end with `.myshopify.com` | `mbuzz-test.myshopify.com` |
| Webhook Signing Secret | password | Required if domain set | `whsec_...` |

**UI Requirements**:
- Show/hide toggle for webhook secret (like password fields)
- "Test Connection" button (optional, sends test webhook)
- Clear validation errors
- Success toast on save

**Screenshot needed**: Final settings UI with Shopify fields

---

### 2. Documentation Page Updates

Update `/docs/platforms-shopify` with comprehensive setup guide.

#### Section Structure

```
1. Overview
   - What mbuzz tracks on Shopify
   - How attribution works (visitor → cart attrs → webhook)

2. Installation
   2.1 Install the App (when available on App Store)
   2.2 Manual Installation (current method)
       - Create webhooks in Shopify admin
       - Configure theme extension
       - Add API key

3. Configuration
   3.1 Get your mbuzz API Key
       [Screenshot: API keys page]

   3.2 Configure Webhooks in Shopify
       - Go to Settings → Notifications → Webhooks
       [Screenshot: Shopify webhook settings page]

       - Create "Order payment" webhook
       [Screenshot: Create webhook modal with orders/paid selected]

       - Create "Customer creation" webhook
       [Screenshot: Create webhook modal with customers/create selected]

       - Copy the webhook signing secret
       [Screenshot: Webhook signing secret location]

   3.3 Add Shopify Settings to mbuzz
       - Go to Dashboard → Settings
       - Enter your Shopify domain
       - Paste webhook signing secret
       [Screenshot: mbuzz settings with Shopify fields]

4. Theme Extension Setup
   4.1 Access Theme Editor
       - Go to Online Store → Themes → Customize
       [Screenshot: Themes page with Customize button highlighted]

   4.2 Enable mbuzz Attribution
       - Click App embeds in sidebar
       - Toggle on "mbuzz Attribution"
       - Enter your API key
       - Save
       [Screenshot: App embeds panel with mbuzz enabled]

5. Checkout Pixel Setup (Required for "Buy it now" flows)
   5.1 Why This is Needed
       - "Buy it now" bypasses the cart, so cart attributes aren't available
       - The checkout pixel captures customer email for attribution fallback
       - Without this, "Buy it now" purchases won't be attributed

   5.2 Add Custom Pixel
       - Go to Settings → Customer events
       [Screenshot: Customer events settings page]

       - Click "Add custom pixel"
       - Enter pixel name: "mbuzz"
       [Screenshot: Add custom pixel modal]

   5.3 Configure Permissions
       - Select "Not required" (simplest option)
       - Or select "Required" with Marketing + Analytics checked
       [Screenshot: Pixel permission settings]

   5.4 Paste Pixel Code
       - Replace YOUR_MBUZZ_API_KEY with your actual API key
       - Paste the following code:

       ```javascript
       // =============================================
       // CONFIGURATION - Replace with your API key
       // Get your API key from: https://mbuzz.co/dashboard/api-keys
       // =============================================
       const API_KEY = "YOUR_MBUZZ_API_KEY";

       // =============================================
       // DO NOT EDIT BELOW THIS LINE
       // =============================================
       const API_URL="https://mbuzz.co/api/v1",VISITOR_KEY="_mbuzz_vid",SESSION_KEY="_mbuzz_sid";async function getVisitorId(){try{return await browser.localStorage.getItem(VISITOR_KEY)||null}catch(x){return null}}async function getSessionId(){try{return await browser.localStorage.getItem(SESSION_KEY)||null}catch(x){return null}}async function trackEvent(type,props={}){const vid=await getVisitorId(),sid=await getSessionId();if(!vid)return;try{await fetch(`${API_URL}/events`,{method:"POST",headers:{Authorization:`Bearer ${API_KEY}`,"Content-Type":"application/json"},body:JSON.stringify({events:[{event_type:type,visitor_id:vid,session_id:sid,timestamp:new Date().toISOString(),properties:props}]})})}catch(x){}}async function identify(email,traits={}){const vid=await getVisitorId();try{await fetch(`${API_URL}/identify`,{method:"POST",headers:{Authorization:`Bearer ${API_KEY}`,"Content-Type":"application/json"},body:JSON.stringify({user_id:email,visitor_id:vid,traits:{email,...traits}})})}catch(x){}}analytics.subscribe("checkout_started",async(evt)=>{const c=evt.data?.checkout,items=c?.lineItems||[];if(items.length>0){const i=items[0];await trackEvent("add_to_cart",{product_id:i.variant?.product?.id,product_title:i.title,price:i.variant?.price?.amount,quantity:i.quantity})}await trackEvent("checkout",{total:c?.totalPrice?.amount,currency:c?.currencyCode,item_count:items.length})});analytics.subscribe("checkout_contact_info_submitted",async(evt)=>{const em=evt.data?.checkout?.email;if(em)await identify(em,{source:"shopify_checkout"})});analytics.subscribe("checkout_completed",async(evt)=>{const em=evt.data?.checkout?.email;if(em)await identify(em,{source:"shopify_checkout_completed"})});
       ```

       **What this pixel tracks:**
       - `checkout_started`: Creates "add_to_cart" + "checkout" events (for "Buy it now" flows)
       - `checkout_contact_info_submitted`: Links visitor to email identity
       - `checkout_completed`: Backup identity link on order completion

   5.5 Save and Connect
       - Click "Add pixel"
       - Click "Save" in the top right
       - Pixel status should show as "Connected"
       [Screenshot: Pixel saved and connected]

6. Testing Your Integration
   6.1 Verify Tracking
       - Visit store with UTM params
       - Open browser console
       - Look for [mbuzz] logs
       [Screenshot: Console showing mbuzz logs]

   6.2 Test Purchase Flow (Add to Cart)
       - Add item to cart
       - Complete checkout (use test gateway)
       - Check mbuzz dashboard for conversion
       [Screenshot: Dashboard showing Shopify conversion]

   6.3 Test Purchase Flow (Buy it Now)
       - Click "Buy it now" on a product (bypasses cart)
       - Complete checkout with email
       - Verify identify call in mbuzz logs
       - Check conversion was attributed via email fallback

7. Troubleshooting
   - "No events appearing" → Check API key, check CORS
   - "No conversions" → Check webhook secret, check domain
   - "Buy it now not working" → Check custom pixel is installed and connected
   - "Duplicate events" → Known issue, being fixed
```

---

### 3. Implementation Tasks

#### Backend

- [x] Add migration if `shopify_domain` and `shopify_webhook_secret` don't exist (they do)
- [x] Webhook receiver implemented (`Webhooks::ShopifyController`)
- [x] Signature verification with HMAC-SHA256
- [x] `Shopify::Handlers::OrderPaid` creates conversions
- [x] Email-based visitor fallback for "Buy it now" flows
- [ ] Add `Accounts::SettingsController#update` action for Shopify fields
- [ ] Add validation: domain must match `*.myshopify.com` format
- [ ] Sanitize domain input (strip https://, trailing slashes)

#### Frontend (Dashboard)

- [ ] Add Shopify section to settings page
- [ ] Domain input field with validation
- [ ] Webhook secret input (password type with show/hide)
- [ ] Save button with loading state
- [ ] Success/error flash messages

#### Theme Extension (mbuzz-shopify)

- [x] Theme extension stores visitor_id in cookies
- [x] Theme extension stores visitor_id in localStorage (for pixel access)
- [x] Theme extension stores session_id in localStorage
- [x] Cart attributes updated with visitor/session IDs
- [x] Deployed to Shopify (v3)

#### Custom Pixel

- [x] Pixel code reads visitor_id from localStorage
- [x] Pixel code reads session_id from localStorage
- [x] `checkout_started` → tracks "add_to_cart" + "checkout" events
- [x] `checkout_contact_info_submitted` → identifies user with email
- [x] `checkout_completed` → backup identify call

#### Documentation

- [ ] Update `app/views/docs/_platforms_shopify.html.erb`
- [ ] Add step-by-step screenshots (capture during UAT)
- [ ] Add troubleshooting section
- [ ] Add "What Gets Tracked" section

---

### 4. Screenshots to Capture

During UAT, capture these screenshots for documentation:

| Screenshot | Description | Filename |
|------------|-------------|----------|
| 1 | Shopify admin webhooks page | `shopify-webhooks-page.png` |
| 2 | Create webhook modal (orders/paid) | `shopify-create-webhook.png` |
| 3 | Webhook signing secret location | `shopify-webhook-secret.png` |
| 4 | Themes page with Customize button | `shopify-themes-page.png` |
| 5 | Theme editor App embeds panel | `shopify-app-embeds.png` |
| 6 | mbuzz extension settings in theme | `shopify-extension-settings.png` |
| 7 | Customer events settings page | `shopify-customer-events.png` |
| 8 | Add custom pixel modal | `shopify-add-pixel-modal.png` |
| 9 | Pixel permission settings | `shopify-pixel-permissions.png` |
| 10 | Pixel code editor | `shopify-pixel-code.png` |
| 11 | Pixel saved and connected | `shopify-pixel-connected.png` |
| 12 | Browser console with mbuzz logs | `shopify-console-logs.png` |
| 13 | mbuzz dashboard with Shopify conversion | `shopify-conversion-dashboard.png` |
| 14 | mbuzz settings page with Shopify fields | `mbuzz-shopify-settings.png` |

**Store screenshots in**: `app/assets/images/docs/shopify/`

---

### 5. Future: App Store Distribution

Once app is on Shopify App Store:
- Webhooks auto-configured via app install
- No manual webhook secret needed (app handles auth)
- Update docs to reflect simplified flow
- Keep manual method documented for custom setups

---

## Acceptance Criteria

- [ ] Customer can configure Shopify domain in dashboard settings
- [ ] Customer can configure webhook secret in dashboard settings
- [ ] Domain validation prevents invalid formats
- [ ] Documentation has complete step-by-step guide
- [x] Documentation includes custom pixel setup for "Buy it now" flows
- [ ] Documentation includes all required screenshots
- [ ] Troubleshooting section covers common issues
- [ ] Both purchase flows work: Add to Cart and Buy it Now
  - [x] Pixel events firing (checkout_started, checkout_contact_info_submitted, checkout_completed)
  - [x] Identity created with email
  - [ ] Webhook creates conversion (blocked - webhook not configured in Shopify admin)
