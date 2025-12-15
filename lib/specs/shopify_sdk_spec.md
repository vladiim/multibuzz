# Shopify Integration Specification

**Status**: Planning
**Last Updated**: 2025-12-17
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
| `autoInit` | boolean | `true` | Track init event on page load |
| `autoIdentify` | boolean | `true` | Auto-identify at checkout/registration |
| `autoAddToCart` | boolean | `true` | Track add to cart events |
| `autoCheckout` | boolean | `true` | Track checkout start |
| `initEventName` | string | `"init"` | Customize init event name |
| `addToCartEventName` | string | `"add_to_cart"` | Customize event name |
| `checkoutEventName` | string | `"checkout"` | Customize event name |

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

New repository: `mbuzz-shopify`

```
mbuzz-shopify/
├── shopify.app.toml              # App manifest
├── package.json
├── app/                          # Remix app
│   ├── routes/
│   │   ├── app._index.tsx        # Settings page
│   │   └── auth.$.tsx            # OAuth
│   └── shopify.server.ts
├── extensions/
│   ├── mbuzz-tracking/           # Theme App Extension
│   │   ├── assets/
│   │   │   └── mbuzz-shopify.js
│   │   ├── blocks/
│   │   │   └── tracking.liquid
│   │   └── shopify.extension.toml
│   └── mbuzz-pixel/              # Web Pixel
│       ├── src/index.js
│       └── shopify.extension.toml
└── prisma/
    └── schema.prisma
```

---

## Backend: Webhook Receiver

### Files to Create

| File | Purpose |
|------|---------|
| `app/controllers/webhooks/shopify_controller.rb` | Receive and verify webhooks |
| `app/services/shopify/webhook_handler.rb` | Route to topic handlers |
| `app/services/shopify/webhook_verifier.rb` | HMAC-SHA256 verification |
| `app/services/shopify/handlers/base.rb` | Base handler class |
| `app/services/shopify/handlers/order_paid.rb` | Create purchase conversion |
| `app/services/shopify/handlers/customer_created.rb` | Create identity record |
| `app/models/shopify_event.rb` | Idempotency tracking |

### Migrations

| Migration | Purpose |
|-----------|---------|
| `add_shopify_fields_to_accounts` | Add `shopify_domain`, `shopify_webhook_secret` |
| `create_shopify_events` | Idempotency table for webhook deduplication |

### Webhook Topics

| Topic | Handler | Action |
|-------|---------|--------|
| `orders/paid` | `OrderPaid` | Create purchase conversion with attribution |
| `customers/create` | `CustomerCreated` | Create identity record |

### Signature Verification

Follow Stripe webhook pattern:
1. Extract `X-Shopify-Hmac-SHA256` header
2. Compute HMAC-SHA256 of raw body with webhook secret
3. Compare with constant-time comparison
4. Reject if mismatch

### Extracting Visitor ID

Parse `note_attributes` array from webhook payload:
```json
{
  "note_attributes": [
    { "name": "_mbuzz_visitor_id", "value": "abc123..." },
    { "name": "_mbuzz_session_id", "value": "xyz789..." }
  ]
}
```

### Idempotency

Use `ShopifyEvent` model to track processed webhook IDs:
- `shopify_event_id` (unique index)
- `topic`
- `processed_at`

---

## Documentation Page

Create documentation at `mbuzz.co/docs/platforms/shopify`.

### Files to Modify

| File | Change |
|------|--------|
| `app/controllers/docs_controller.rb` | Add "platforms-shopify" to ALLOWED_PAGES |
| `app/views/docs/_platforms_shopify.html.erb` | Create documentation content |

### Documentation Sections

1. **Installation** - Install from Shopify App Store
2. **Configuration** - Enter API key from mbuzz dashboard
3. **Tracked Events** - init, identify, add_to_cart, checkout, order
4. **JavaScript API** - Custom events and configuration
5. **Troubleshooting** - Common issues and solutions

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

### Phase 1: Webhook Receiver (Backend)

- [ ] Create `Shopify::WebhookVerifier` service
- [ ] Create `Shopify::WebhookHandler` router
- [ ] Create `Shopify::Handlers::OrderPaid` handler
- [ ] Create `Shopify::Handlers::CustomerCreated` handler
- [ ] Create `ShopifyEvent` model for idempotency
- [ ] Add migrations
- [ ] Create `Webhooks::ShopifyController`
- [ ] Add route
- [ ] Write unit tests

### Phase 2: Documentation Page

- [ ] Add "platforms-shopify" to DocsController ALLOWED_PAGES
- [ ] Create `_platforms_shopify.html.erb` partial
- [ ] Document installation, configuration, events, JS API

### Phase 3: Theme App Extension (mbuzz-shopify repo)

- [ ] Scaffold app with Shopify CLI
- [ ] Generate theme extension
- [ ] Implement cookie management
- [ ] Implement cart attribute storage
- [ ] Implement init event (UTM capture)
- [ ] Implement add_to_cart tracking
- [ ] Implement checkout tracking
- [ ] Implement form interception for auto-identify
- [ ] Create Liquid block with settings
- [ ] Test with development store

### Phase 4: Web Pixel

- [ ] Generate Web Pixel extension
- [ ] Subscribe to `checkout_contact_info_submitted`
- [ ] Implement identify call from pixel
- [ ] Test checkout flow end-to-end

### Phase 5: App Settings Page

- [ ] Create settings route in Remix app
- [ ] Build API key input UI
- [ ] Implement connection test
- [ ] Deploy

### Phase 6: End-to-End Testing

- [ ] Install on real test store
- [ ] Verify init event with UTM
- [ ] Verify add_to_cart tracking
- [ ] Verify checkout tracking
- [ ] Verify auto-identify at checkout
- [ ] Verify purchase webhook creates conversion
- [ ] Verify attribution appears in dashboard

### Phase 7: App Store Submission

- [ ] Write App Store listing
- [ ] Create screenshots
- [ ] Submit for review
- [ ] Update `sdk_registry.yml` to `live`

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No visitor_id in cart | Log warning, create conversion without attribution |
| Webhook replay | Skip via idempotency table |
| JavaScript blocked | Webhook still fires but no attribution |
| Cross-device purchase | Use identify at login to link |
| Guest checkout | Auto-identify from checkout email |
| Cart abandoned then recovered | visitor_id persists in cart attributes |

---

## Testing Checklist

### Webhook Handler Tests

- [ ] Signature validation rejects invalid signatures
- [ ] Signature validation accepts valid signatures
- [ ] Idempotency prevents duplicate processing
- [ ] OrderPaid creates conversion with correct revenue
- [ ] OrderPaid extracts visitor_id from note_attributes
- [ ] CustomerCreated creates identity record
- [ ] Missing visitor_id handles gracefully

### Client-Side Tests (Manual)

- [ ] Fresh visit sets visitor cookie
- [ ] Fresh visit fires init event with UTM
- [ ] Return visit uses existing visitor cookie
- [ ] Session cookie expires after 30 min inactivity
- [ ] Session cookie extends on activity
- [ ] Cart attributes updated on page load
- [ ] Add to cart fires event with product details
- [ ] Checkout fires event
- [ ] Form submit triggers identify
- [ ] Checkout email triggers identify

### End-to-End Tests

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
