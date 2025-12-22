# Shopify Integration Specification

**Status**: Ready for UAT
**Last Updated**: 2025-12-18
**Target**: Shopify App Store Distribution

---

## Overview

Full Shopify App for multi-touch attribution tracking. Designed for App Store distribution with zero-code installation.

### Attribution Funnel

| Event | Trigger | Purpose |
|-------|---------|---------|
| `init` | First page load | Capture UTM parameters, start session |
| `identify` | Login, register, checkout email | Link visitor to customer |
| `add_to_cart` | Add item to cart | Funnel tracking |
| `checkout` | Begin checkout | Funnel tracking |
| `order` | Purchase complete (webhook) | **Conversion with revenue** |

---

## The Cookie Problem

Shopify webhooks (`orders/paid`) fire server-side and don't have access to browser cookies.

### Solution: Cart Note Attributes

Store `visitor_id` in Shopify's cart `note_attributes`. These persist through checkout and appear in webhook payloads.

**Flow:**
1. Client-side JS generates `visitor_id` cookie
2. JS stores `visitor_id` in cart via `/cart/update.js`
3. Customer completes checkout
4. Webhook payload includes `note_attributes` with `visitor_id`
5. Backend links conversion to visitor's session for attribution

---

## Architecture

```
Shopify App (mbuzz-shopify)          mbuzz Backend
===========================          ==============

1. Theme App Extension       ---->   POST /api/v1/events
   - Set cookies                     (init, add_to_cart, checkout)
   - Store IDs in cart attrs
   - Track events             ---->  POST /api/v1/identify
   - Auto-identify on forms          (customer linkage)

2. Web Pixel                 ---->   POST /api/v1/identify
   - checkout_contact_info           (checkout email auto-identify)

3. Checkout
   - note_attributes preserved

4. Webhook Subscription      ---->   POST /webhooks/shopify
   - orders/paid                     - Extract visitor_id
   - customers/create                - Create conversion
```

---

## Auto-Identification

Automatically link visitors to customers when they provide their email.

### Identification Triggers

| Trigger | Method | Details |
|---------|--------|---------|
| Checkout email | Web Pixel | `checkout_contact_info_submitted` event |
| Registration form | Theme Extension | Intercept form submit on `/account/register` |
| Login | Theme Extension | Detect `customer.id` in Liquid context |
| Webhook | Server-side | `customers/create` webhook as backup |

### Implementation

- **Web Pixel**: Runs in sandboxed iframe, subscribes to checkout events, can make API calls
- **Theme Extension**: Listens for form submissions, captures email before submit
- Both work together for complete coverage

---

## JavaScript API

Merchants can customize default behavior and track custom events.

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `autoPageView` | boolean | `true` | Track page view on load |
| `autoIdentify` | boolean | `true` | Auto-identify logged in customers |
| `autoAddToCart` | boolean | `true` | Track add to cart events |
| `debug` | boolean | `false` | Log to console |

### Custom Events

```javascript
mbuzz.event('viewed_pricing', { plan: 'enterprise' });
```

### Custom Conversions

```javascript
mbuzz.conversion('demo_request', { revenue: 0 });
```

### Manual Identification

```javascript
mbuzz.identify(customerId, { email: 'customer@example.com' });
```

---

## Shopify App Structure

Repository: `/Users/vlad/code/mbuzz-shopify` (created 2025-12-17)

```
mbuzz-shopify/
├── shopify.app.toml              # App manifest (webhooks → mbuzz.co)
├── package.json
├── app/                          # Remix app
│   ├── root.tsx
│   ├── shopify.server.ts         # Shopify API client + Prisma
│   └── routes/
│       ├── app._index.tsx        # Settings page (API key config)
│       ├── app.tsx               # App layout with Polaris
│       ├── auth.$.tsx            # OAuth callback
│       └── webhooks.tsx          # Webhook handler (fallback)
├── extensions/
│   ├── mbuzz-tracking/           # Theme App Extension
│   │   ├── assets/
│   │   │   └── mbuzz-shopify.js  # Client tracking (~390 lines)
│   │   ├── blocks/
│   │   │   └── tracking.liquid   # Theme block with settings
│   │   └── shopify.extension.toml
│   └── mbuzz-pixel/              # Web Pixel Extension
│       ├── src/
│       │   └── index.js          # Checkout identify (~100 lines)
│       └── shopify.extension.toml
├── prisma/
│   └── schema.prisma             # Session + ShopSettings storage
├── tsconfig.json
├── vite.config.ts
└── README.md
```

---

## Backend: Webhook Receiver

### Files Created ✅

| File | Purpose | Status |
|------|---------|--------|
| `app/constants/shopify.rb` | Centralized constants | ✅ Done |
| `app/controllers/webhooks/shopify_controller.rb` | Receive and verify webhooks | ✅ Done |
| `app/services/shopify/webhook_handler.rb` | Route to topic handlers | ✅ Done |
| `app/services/shopify/webhook_verifier.rb` | HMAC-SHA256 verification | ✅ Done |
| `app/services/shopify/handlers/base.rb` | Base handler class | ✅ Done |
| `app/services/shopify/handlers/order_paid.rb` | Create purchase conversion | ✅ Done |
| `app/services/shopify/handlers/customer_created.rb` | Link visitor to identity | ✅ Done |

### Migrations ✅

| Migration | Purpose | Status |
|-----------|---------|--------|
| `add_shopify_fields_to_accounts` | Add `shopify_domain`, `shopify_webhook_secret` | ✅ Done |

**Note:** Idempotency uses conversion properties (`shopify_order_id`) instead of separate table.

### Webhook Topics

| Topic | Handler | Action |
|-------|---------|--------|
| `orders/paid` | `OrderPaid` | Create purchase conversion with attribution |
| `customers/create` | `CustomerCreated` | Link visitor to identity |

### Test Coverage ✅

| Test File | Tests | Status |
|-----------|-------|--------|
| `test/controllers/webhooks/shopify_controller_test.rb` | 7 tests | ✅ Passing |
| `test/services/shopify/webhook_verifier_test.rb` | 6 tests | ✅ Passing |
| `test/services/shopify/handlers/order_paid_test.rb` | 5 tests | ✅ Passing |
| `test/services/shopify/handlers/customer_created_test.rb` | 5 tests | ✅ Passing |

**Total: 23 tests, all passing**

---

## Documentation Page ✅

Created at `mbuzz.co/docs/platforms-shopify`.

| File | Status |
|------|--------|
| `app/controllers/docs_controller.rb` | ✅ Updated (added "platforms-shopify") |
| `app/views/docs/_platforms_shopify.html.erb` | ✅ Created |

---

## Cookie Specifications

Follow existing SDK cookie spec from `lib/specs/sdk_rollout.md`:

| Cookie | Name | Format | Expiry |
|--------|------|--------|--------|
| Visitor ID | `_mbuzz_vid` | 64 hex chars | 2 years |
| Session ID | `_mbuzz_sid` | 64 hex chars | 30 min sliding |

### Cart Attributes

| Attribute | Value |
|-----------|-------|
| `_mbuzz_visitor_id` | Same as cookie |
| `_mbuzz_session_id` | Same as cookie |

---

## Implementation Phases

### Phase 1: Webhook Receiver (Backend) ✅ COMPLETE

- [x] Create `Shopify::WebhookVerifier` service
- [x] Create `Shopify::WebhookHandler` router
- [x] Create `Shopify::Handlers::OrderPaid` handler
- [x] Create `Shopify::Handlers::CustomerCreated` handler
- [x] Add migrations (shopify_domain, shopify_webhook_secret)
- [x] Create `Webhooks::ShopifyController`
- [x] Add route (`POST /webhooks/shopify`)
- [x] Write unit tests (23 tests passing)

### Phase 2: Documentation Page ✅ COMPLETE

- [x] Add "platforms-shopify" to DocsController ALLOWED_PAGES
- [x] Create `_platforms_shopify.html.erb` partial

### Phase 3: Theme App Extension (mbuzz-shopify repo) ✅ SCAFFOLDED

- [x] Create app structure (Remix + Shopify)
- [x] Create theme extension structure
- [x] Implement cookie management (`_mbuzz_vid`, `_mbuzz_sid`)
- [x] Implement cart attribute storage
- [x] Implement session tracking (UTM capture)
- [x] Implement page view tracking
- [x] Implement add_to_cart tracking (fetch intercept + form submit)
- [x] Implement auto-identify for logged in customers
- [x] Create Liquid block with settings UI
- [ ] **NEXT: Authenticate with Shopify CLI**
- [ ] Test with development store

### Phase 4: Web Pixel ✅ COMPLETE

- [x] Generate Web Pixel extension
- [x] Subscribe to `checkout_contact_info_submitted`
- [x] Subscribe to `checkout_completed` (backup)
- [x] Implement identify call from pixel
- [ ] Test checkout flow end-to-end

### Phase 5: App Settings Page ✅ SCAFFOLDED

- [x] Create settings route in Remix app
- [x] Build API key input UI (Polaris)
- [x] Prisma model for ShopSettings
- [ ] Deploy to Fly.io

### Phase 6: End-to-End Testing

- [ ] Install on real test store
- [ ] Verify session tracking with UTM
- [ ] Verify add_to_cart tracking
- [ ] Verify auto-identify at checkout
- [ ] Verify purchase webhook creates conversion
- [ ] Verify attribution appears in dashboard

### Phase 7: App Store Submission

- [ ] Write App Store listing
- [ ] Create screenshots
- [ ] Submit for review
- [ ] Update `sdk_registry.yml` to `live`

---

## Next Steps: UAT

### Prerequisites

1. **Create Shopify Partner Account** (if not already done)
   - Go to https://partners.shopify.com
   - Sign up (free)

2. **Create Development Store**
   - In Partners Dashboard → Stores → Add store → Development store

### Setup Steps

1. **Authenticate Shopify CLI**
   ```bash
   cd /Users/vlad/code/mbuzz-shopify
   npm install
   npm run dev  # Will prompt for Shopify auth
   ```

2. **Select development store** when prompted

3. **Configure Extensions**
   - Theme Extension: Enable in theme customizer, enter mbuzz API key
   - Web Pixel: Configure in app settings with API key

### UAT Checklist

1. **Test theme extension**
   - Verify `_mbuzz_vid` and `_mbuzz_sid` cookies set
   - Verify cart attributes contain visitor/session IDs
   - Verify page_view events sent to mbuzz

2. **Test add to cart**
   - Add product to cart
   - Verify add_to_cart event in mbuzz dashboard

3. **Test checkout flow**
   - Complete checkout with email
   - Verify Web Pixel sends identify call
   - Verify webhook creates conversion in mbuzz

4. **Verify attribution**
   - Start with UTM params: `?utm_source=test&utm_medium=cpc`
   - Complete full funnel
   - Check mbuzz dashboard shows conversion with attribution

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No visitor_id in cart | Return warning, skip conversion |
| Webhook replay | Idempotency via `shopify_order_id` in conversion properties |
| JavaScript blocked | Webhook still fires but no attribution |
| Cross-device purchase | Use identify at login to link |
| Guest checkout | Auto-identify from checkout email (Web Pixel) |
| Cart abandoned then recovered | visitor_id persists in cart attributes |

---

## Testing Checklist

### Webhook Handler Tests ✅

- [x] Signature validation rejects invalid signatures
- [x] Signature validation accepts valid signatures
- [x] Idempotency prevents duplicate processing
- [x] OrderPaid creates conversion with correct revenue
- [x] OrderPaid extracts visitor_id from note_attributes
- [x] CustomerCreated links visitor to identity
- [x] Missing visitor_id handles gracefully (returns warning)

### Client-Side Tests (Manual) - PENDING

**Theme Extension:**
- [ ] Fresh visit sets visitor cookie
- [ ] Fresh visit fires session event with UTM
- [ ] Return visit uses existing visitor cookie
- [ ] Session cookie expires after 30 min inactivity
- [ ] Session cookie extends on activity
- [ ] Cart attributes updated on page load
- [ ] Add to cart fires event with product details
- [ ] Auto-identify fires for logged-in customer

**Web Pixel:**
- [ ] Checkout email triggers identify (`checkout_contact_info_submitted`)
- [ ] Checkout completion triggers identify backup (`checkout_completed`)

### End-to-End Tests - PENDING

- [ ] UTM click → browse → add to cart → checkout → purchase → conversion with attribution
- [ ] Guest checkout with auto-identify
- [ ] Returning customer with existing identity
- [ ] Mobile checkout flow

---

## References

### Shopify Documentation

- [Theme App Extensions](https://shopify.dev/docs/apps/online-store/theme-app-extensions)
- [Web Pixels](https://shopify.dev/docs/apps/marketing/pixels)
- [Cart API](https://shopify.dev/docs/api/ajax/reference/cart)
- [Webhook Topics](https://shopify.dev/docs/api/admin-rest/2024-10/resources/webhook)
- [Customer Events](https://shopify.dev/docs/api/web-pixels-api/standard-events)

### Existing Patterns

- `app/controllers/webhooks/stripe_controller.rb` - Webhook verification pattern
- `app/services/billing/webhook_handler.rb` - Handler routing pattern
- `app/services/conversions/tracking_service.rb` - Conversion creation
- `lib/specs/sdk_rollout.md` - Cookie specifications
