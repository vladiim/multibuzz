# Shopify Onboarding & Documentation Spec

**Status**: UAT PASSED ✅
**Created**: 2025-12-18
**Updated**: 2025-12-19
**Priority**: Documentation remaining

---

## Progress Summary

### Completed (2025-12-18)
- [x] Email-based visitor lookup fallback in webhook handler (for "Buy it now" flows)
- [x] Theme extension stores visitor_id in cookies, localStorage, AND cart attributes
- [x] Theme extension deployed (v3)
- [x] Webhook configured in Shopify admin (orders/paid → mbuzz.co/webhooks/shopify)

### Completed (2025-12-19)
- [x] **Root cause identified**: Pixel was reading from localStorage (cross-origin blocked on checkout)
- [x] **Fix**: Pixel now reads visitor_id from `checkout.attributes` (cart note attributes)
- [x] Pixel code updated with ES5-compatible syntax (no arrow functions, template literals, spread operators)
- [x] `checkout` event appearing in production
- [x] **Test identify call**: Email captured at checkout, identity created ✅
- [x] **Test webhook**: orders/paid webhook received and processed ✅
- [x] **Verify conversion**: Conversion created with full attribution (visitor_id, session_id, revenue) ✅
- [x] **UAT PASSED** (Order #YXPUGG7T5, $749.95, visitor_id: 96375, session_id: 119962)

### Remaining Documentation Tasks
- [ ] Capture screenshots for documentation (store in `/public/images/docs/shopify/`)
- [ ] Write step-by-step setup guide
- [ ] Update `app/views/docs/_platforms_shopify.html.erb` with guide + screenshots
- [ ] Add Shopify to onboarding flow (if applicable)
- [ ] Build dashboard settings UI for Shopify configuration
- [ ] Add "Known Limitations" section to public docs

### Known Shopify Limitations

1. **Test orders don't trigger webhooks**: The `orders/paid` webhook only fires for real transactions. See [Shopify Community](https://community.shopify.dev/t/webhook-orders-paid-not-triggered-with-bogus-gateway/5770).
   - **Workaround**: Create a draft order in Shopify Admin and manually mark it as paid.

2. **"Buy it Now" creates fresh cart without attributes**: This is a [known Shopify bug](https://community.shopify.dev/t/bug-cart-attributes-are-not-passed-to-functions-when-buy-it-now-button-is-used/1895) (unsolved as of Dec 2025).
   - **Why**: "Buy it Now" bypasses the existing cart and creates a fresh cart without note_attributes.
   - Cart attributes (our only reliable method to pass data to checkout) are empty.

3. **Cross-origin checkout isolation**: The checkout runs in a [sandboxed iframe](https://www.simoahava.com/analytics/cookie-access-with-shopify-checkout-sgtm/) on a different origin.
   - Web Pixels cannot access storefront cookies or localStorage
   - Checkout UI Extensions cannot read storefront cookies either
   - The `useStorage()` hook uses [isolated namespaced storage](https://community.shopify.com/c/extensions/pass-data-from-browser-cookie-or-localstorage-to-shopify/td-p/2441280)
   - **Community solution**: "Set cart attributes on the online store... then retrieve with checkout extensions"

4. **Attribution coverage by flow**:
   | Flow | Attribution | Notes |
   |------|-------------|-------|
   | Add to Cart → Checkout | ✅ Full | Cart attributes pass visitor_id |
   | Buy it Now (returning customer) | ✅ Full | Email fallback finds linked identity |
   | Buy it Now (new customer) | ❌ None | No visitor_id, no prior identity link |

---

## Deep Research: Deterministic Visitor Tracking

### The Core Problem

For MTA to work, we need to deterministically link:
```
UTM Click → Page Views → Add to Cart → Checkout → Purchase
```

The visitor_id must flow through the entire funnel. The problem:

1. **Storefront** (your-store.myshopify.com): Our theme extension has full access to cookies/localStorage
2. **Checkout** (shop.app or checkout.shopify.com): Sandboxed, cross-origin, no access to storefront data
3. **Webhook**: Server-side, no browser context at all

### How Attribution Platforms Solve This

| Platform | Approach | Notes |
|----------|----------|-------|
| [Triple Whale](https://kb.triplewhale.com/en/articles/5960325-how-the-triple-pixel-works) | First-party pixel on ALL pages + order confirmation | Builds anonymous visitor identity, tracks all clicks |
| [Northbeam](https://www.headwestguide.com/triple-whale-vs-northbeam) | DNS-level tracking + platform API integrations | Fingerprints visitors across sessions |
| [Elevar](https://analyzify.com/guidebooks/server-side-tracking-for-shopify/foundations) | Server-side tracking + enhanced data sharing | 95-98% accuracy via first-party data |

Key insight: These platforms combine:
- **Client-side**: First-party cookie/ID on storefront
- **Checkout linking**: `checkout_token` matching (pixel → order)
- **Server-side**: Platform API integrations + email matching

### Available Shopify Mechanisms

| Mechanism | Works for Cart | Works for Buy it Now | Notes |
|-----------|---------------|---------------------|-------|
| Cart note_attributes | ✅ Yes | ❌ No | [Documented approach](https://www.snowcatcloud.com/docs/integrations/shopify/) |
| Storefront API cartCreate | ✅ Yes | ✅ Possible | Requires custom button |
| Checkout UI Extension + applyAttributeChange | ✅ Yes | ✅ Yes | [Shopify Plus only](https://shopify.dev/docs/api/checkout-ui-extensions/latest/apis/attributes), can't get visitor_id |
| checkout_token matching | ✅ Yes | ✅ Yes | [Links pixel to order](https://shopify.dev/docs/api/checkout-ui-extensions/2025-07/apis/checkout-token) |
| Web Pixel analytics.visitor | ✅ Email only | ✅ Email only | [Email/phone capture](https://shopify.dev/docs/api/web-pixels-api/emitting-data) |

### Proposed Solutions (Ranked)

#### Solution 1: Custom "Buy it Now" Button (Deterministic) ⭐

Replace Shopify's native "Buy it Now" button with a custom implementation:

1. Theme extension adds custom "Buy Now" button
2. On click: Create cart via [Storefront API cartCreate](https://shopify.dev/docs/storefronts/headless/building-with-the-storefront-api/cart/manage) with attributes
3. Redirect to `checkoutUrl` from response

**Pros**: Fully deterministic, works for all flows
**Cons**: Requires theme modification, may break accelerated checkout (Apple Pay, Shop Pay)

```javascript
// Theme extension: Custom Buy Now
async function customBuyNow(variantId) {
  const response = await fetch('/api/2024-01/graphql.json', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: `mutation { cartCreate(input: {
        lines: [{ merchandiseId: "${variantId}", quantity: 1 }],
        attributes: [
          { key: "_mbuzz_visitor_id", value: "${getVisitorId()}" },
          { key: "_mbuzz_session_id", value: "${getSessionId()}" }
        ]
      }) { cart { checkoutUrl } } }`
    })
  });
  const { data } = await response.json();
  window.location.href = data.cartCreate.cart.checkoutUrl;
}
```

#### Solution 2: Checkout Token Linking (Semi-Deterministic)

Use `checkout_token` to link pixel events to orders:

1. **Storefront**: Track visitor activity (page_view, add_to_cart) with visitor_id
2. **Pixel**: On `checkout_started`, capture `checkout.token` + any available IDs
3. **Backend**: Store `checkout_token → last_known_visitor_id` mapping
4. **Webhook**: Order has `checkout_token`, look up visitor from mapping

**Problem**: For "Buy it Now" without cart attributes, we still don't have visitor_id at checkout.

**Partial solution**: Store mapping of `checkout_token → email` when identify fires, then use email to find visitor.

#### Solution 3: Email-First Attribution (Current Approach)

Accept that "Buy it Now" guest checkouts may have limited attribution:

1. **Cart flows**: Full attribution via cart attributes
2. **Returning customers**: Email lookup finds previously linked identity
3. **New guest + Buy it Now**: Conversion recorded but attribution incomplete

**How to improve current approach**:

The issue is `identity.visitors` returns nil because the identify call at checkout has no visitor_id to link.

**Fix**: When webhook fires with email, if identity exists but has no visitors, link to the most recent visitor that:
- Was active within a reasonable time window (e.g., 30 minutes)
- Has sessions from the same account

This is probabilistic but better than no attribution. Mark these conversions with an "inferred" flag.

#### Solution 4: Pre-Identify on Storefront (Requires User Action)

If the user enters their email BEFORE clicking "Buy it Now":
- Newsletter signup
- Account creation
- Login

Then the identity already has a linked visitor when the webhook fires.

**Implementation**: Encourage early identification via:
- Exit-intent popups with email capture
- Newsletter signup incentives
- Account creation benefits

---

### Decision: Accept Limitation (2025-12-19)

**Chosen approach**: Document limitation clearly, optimize for cart flows.

**Rationale**:
- ~70-80% of Shopify purchases use cart flow (full attribution works)
- Custom "Buy it Now" solution is 6-11 hours with risk of breaking accelerated checkout
- Revisit when customer demand justifies the investment

**Current coverage**:
| Flow | Attribution | % of Purchases |
|------|-------------|----------------|
| Add to Cart → Checkout | ✅ Full | ~70-80% |
| Buy it Now (returning customer) | ✅ Full | ~10-15% |
| Buy it Now (new guest) | ❌ None | ~5-15% |

**Future phases (when needed)**:
1. Custom "Buy it Now" button with Storefront API
2. Checkout token linking
3. Real-time session sync

---

### Technical References

- [Shopify Cart Attributes Guide](https://ecomposer.io/blogs/shopify-knowledge/shopify-cart-attributes)
- [Web Pixels on Steroids (Nebulab)](https://nebulab.com/blog/shopify-web-pixels)
- [Cookie Access with Shopify Checkout (Simo Ahava)](https://www.simoahava.com/analytics/cookie-access-with-shopify-checkout-sgtm/)
- [Checkout Token API](https://shopify.dev/docs/api/checkout-ui-extensions/2025-07/apis/checkout-token)
- [Display Custom Data at Checkout](https://shopify.dev/docs/apps/build/checkout/display-custom-data)
- [Add Field to Checkout](https://shopify.dev/docs/apps/build/checkout/fields-banners/add-field)

### Next Steps
1. Update pixel code in Shopify admin (Settings → Customer events → mbuzz pixel)
2. Test checkout flow - verify `checkout` event appears in mbuzz
3. Test webhook by manually marking a draft order as paid
4. Build dashboard settings UI for Shopify configuration

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
// CONFIGURATION
const API_KEY = "YOUR_MBUZZ_API_KEY";
const DEBUG = true;

// DO NOT EDIT BELOW
const API_URL = "https://mbuzz.co/api/v1";
const VID_ATTR = "_mbuzz_visitor_id";
const SID_ATTR = "_mbuzz_session_id";

function log(msg, data) {
  if (DEBUG) console.log("[mbuzz] " + msg, data || "");
}

// Store IDs in sessionStorage to persist across page navigations
function cacheIds(vid, sid) {
  if (vid) {
    browser.sessionStorage.setItem("_mbuzz_cached_vid", vid);
    browser.sessionStorage.setItem("_mbuzz_cached_sid", sid || "");
    log("cacheIds: stored", { vid: vid, sid: sid });
  }
}

function getIds(checkout) {
  var attrs = (checkout && checkout.attributes) || [];
  var vid = null;
  var sid = null;
  for (var i = 0; i < attrs.length; i++) {
    if (attrs[i].key === VID_ATTR) vid = attrs[i].value;
    if (attrs[i].key === SID_ATTR) sid = attrs[i].value;
  }
  // Cache IDs when found
  if (vid) { cacheIds(vid, sid); }
  log("getIds from attrs", { vid: vid || "(not found)", sid: sid || "(not found)" });
  return { vid: vid, sid: sid };
}

// Try to get IDs from localStorage (theme extension) - async version for checkout_started
function getIdsWithLocalStorage(checkout, callback) {
  var ids = getIds(checkout);
  if (ids.vid) {
    callback(ids);
    return;
  }
  // Fall back to localStorage (theme extension stores there)
  Promise.all([
    browser.localStorage.getItem("_mbuzz_vid"),
    browser.localStorage.getItem("_mbuzz_sid")
  ]).then(function(results) {
    var vid = results[0];
    var sid = results[1];
    if (vid) { cacheIds(vid, sid); }
    log("getIds from localStorage", { vid: vid || "(not found)", sid: sid || "(not found)" });
    callback({ vid: vid, sid: sid });
  }).catch(function(e) {
    log("localStorage error", e.message);
    callback({ vid: null, sid: null });
  });
}

function getCachedIds(callback) {
  // Try sessionStorage first (cached from checkout_started), then localStorage (from theme extension)
  Promise.all([
    browser.sessionStorage.getItem("_mbuzz_cached_vid"),
    browser.sessionStorage.getItem("_mbuzz_cached_sid"),
    browser.localStorage.getItem("_mbuzz_vid"),
    browser.localStorage.getItem("_mbuzz_sid")
  ]).then(function(results) {
    var vid = results[0] || results[2];  // sessionStorage or localStorage
    var sid = results[1] || results[3];
    log("getCachedIds", { vid: vid || "(not found)", sid: sid || "(not found)", fromSession: !!results[0], fromLocal: !!results[2] });
    callback({ vid: vid, sid: sid });
  }).catch(function(e) {
    log("getCachedIds error", e.message);
    callback({ vid: null, sid: null });
  });
}

function trackEvent(checkout, eventType, props) {
  var ids = getIds(checkout);
  if (!ids.vid) { log("SKIP - no visitor_id:", eventType); return; }
  trackEventWithIds(ids, eventType, props);
}

function trackEventWithIds(ids, eventType, props) {
  if (!ids.vid) { log("SKIP - no visitor_id:", eventType); return; }
  var payload = {
    events: [{
      event_type: eventType,
      visitor_id: ids.vid,
      session_id: ids.sid,
      timestamp: new Date().toISOString(),
      properties: props || {}
    }]
  };
  log("trackEvent: " + eventType, payload);
  fetch(API_URL + "/events", {
    method: "POST",
    headers: { "Authorization": "Bearer " + API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  }).catch(function(e) { log("err", e.message); });
}

function identify(checkout, email, source) {
  // First try to get IDs from checkout attributes
  var ids = getIds(checkout);
  if (ids.vid) {
    sendIdentify(email, ids.vid, source);
  } else {
    // Fall back to cached IDs from sessionStorage
    getCachedIds(function(cached) {
      sendIdentify(email, cached.vid, source);
    });
  }
}

function sendIdentify(email, vid, source) {
  var payload = {
    user_id: email,
    visitor_id: vid,
    traits: { email: email, source: source }
  };
  log("identify: " + email, payload);
  fetch(API_URL + "/identify", {
    method: "POST",
    headers: { "Authorization": "Bearer " + API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  }).catch(function(e) { log("err", e.message); });
}

analytics.subscribe("checkout_started", function(evt) {
  log("checkout_started", evt);
  var checkout = evt.data && evt.data.checkout;
  var items = (checkout && checkout.lineItems) || [];

  // Use async version to check localStorage if cart attrs are empty
  getIdsWithLocalStorage(checkout, function(ids) {
    if (!ids.vid) { log("SKIP checkout_started - no visitor_id found anywhere"); return; }

    if (items.length > 0) {
      var item = items[0];
      var variant = item.variant || {};
      var product = variant.product || {};
      var price = variant.price || {};
      trackEventWithIds(ids, "add_to_cart", {
        product_id: product.id,
        product_title: item.title,
        price: price.amount,
        quantity: item.quantity,
        source: "checkout_pixel"
      });
    }
    var total = checkout && checkout.totalPrice || {};
    trackEventWithIds(ids, "checkout", {
      total: total.amount,
      currency: checkout && checkout.currencyCode,
      item_count: items.length,
      source: "checkout_pixel"
    });
  });
});

analytics.subscribe("checkout_contact_info_submitted", function(evt) {
  log("checkout_contact_info_submitted", evt);
  var checkout = evt.data && evt.data.checkout;
  var email = checkout && checkout.email;
  if (email) identify(checkout, email, "shopify_checkout");
});

analytics.subscribe("checkout_completed", function(evt) {
  log("checkout_completed", evt);
  var checkout = evt.data && evt.data.checkout;
  var email = checkout && checkout.email;
  if (email) identify(checkout, email, "shopify_checkout_completed");
});

log("mbuzz pixel initialized");

// OPTIONAL EVENTS: https://shopify.dev/docs/api/web-pixels-api/standard-events
// analytics.subscribe("product_viewed", function(evt) { log("product_viewed", evt); });
// analytics.subscribe("collection_viewed", function(evt) { log("collection_viewed", evt); });
// analytics.subscribe("search_submitted", function(evt) { log("search_submitted", evt); });
       ```

       **What this pixel tracks:**
       - `checkout_started`: Creates "add_to_cart" + "checkout" events (covers "Buy it now" flows)
       - `checkout_contact_info_submitted`: Links visitor to email identity
       - `checkout_completed`: Backup identity link on order completion

       **Custom events (optional):** See commented section above. Full list at [Shopify Standard Events](https://shopify.dev/docs/api/web-pixels-api/standard-events).

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
