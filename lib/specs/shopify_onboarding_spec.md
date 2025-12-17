# Shopify Onboarding & Documentation Spec

**Status**: Pending
**Created**: 2025-12-18
**Priority**: High (blocking UAT completion)

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

5. Testing Your Integration
   5.1 Verify Tracking
       - Visit store with UTM params
       - Open browser console
       - Look for [mbuzz] logs
       [Screenshot: Console showing mbuzz logs]

   5.2 Test Purchase Flow
       - Add item to cart
       - Complete checkout (use test gateway)
       - Check mbuzz dashboard for conversion
       [Screenshot: Dashboard showing Shopify conversion]

6. Troubleshooting
   - "No events appearing" → Check API key, check CORS
   - "No conversions" → Check webhook secret, check domain
   - "Duplicate events" → Known issue, being fixed
```

---

### 3. Implementation Tasks

#### Backend

- [ ] Add migration if `shopify_domain` and `shopify_webhook_secret` don't exist (they do)
- [ ] Add `Accounts::SettingsController#update` action for Shopify fields
- [ ] Add validation: domain must match `*.myshopify.com` format
- [ ] Sanitize domain input (strip https://, trailing slashes)

#### Frontend (Dashboard)

- [ ] Add Shopify section to settings page
- [ ] Domain input field with validation
- [ ] Webhook secret input (password type with show/hide)
- [ ] Save button with loading state
- [ ] Success/error flash messages

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
| 7 | Browser console with mbuzz logs | `shopify-console-logs.png` |
| 8 | mbuzz dashboard with Shopify conversion | `shopify-conversion-dashboard.png` |
| 9 | mbuzz settings page with Shopify fields | `mbuzz-shopify-settings.png` |

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
- [ ] Documentation includes all required screenshots
- [ ] Troubleshooting section covers common issues
