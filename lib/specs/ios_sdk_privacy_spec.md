# iOS SDK Privacy & MTA Specification

**Status**: Research Complete - Architectural Decision Required
**Last Updated**: 2025-12-18
**Target**: iOS 14.5+, Swift 5.5+

---

## Overview

This document analyzes the implications of implementing mbuzz as an iOS SDK, specifically addressing Apple's privacy restrictions and their impact on Multi-Touch Attribution (MTA). The core challenge: **iOS privacy controls fundamentally conflict with traditional cross-session/cross-app attribution.**

### The Core Problem

Traditional MTA relies on:
1. **Consistent user identity** across touchpoints
2. **Cross-channel visibility** (web → ad → app → purchase)
3. **Deterministic matching** (same user ID everywhere)

iOS 14.5+ breaks all three for non-consented users through App Tracking Transparency (ATT).

---

## iOS Privacy Restrictions

### App Tracking Transparency (ATT) - iOS 14.5+

**Requirement**: Apps must request explicit user permission before tracking across apps/websites owned by other companies.

**Consent Rate**: ~20-25% opt-in (75-80% decline)

**Enforcement**: App Store rejection for violations

```swift
// Required prompt before accessing IDFA
import AppTrackingTransparency

ATTrackingManager.requestTrackingAuthorization { status in
    switch status {
    case .authorized:
        // Can use IDFA for cross-app tracking
        let idfa = ASIdentifierManager.shared().advertisingIdentifier
    case .denied, .restricted, .notDetermined:
        // Cannot track across apps/websites
        break
    }
}
```

### What Counts as "Tracking" Under Apple's Definition

Apple defines tracking as:
1. Linking user/device data from your app with third-party data for targeted advertising
2. Sharing user/device data with data brokers
3. Using device signals (fingerprinting) to identify users across apps

**IDFA Without Consent** = App Store Rejection

### Prohibited Techniques

| Technique | Status | Consequence |
|-----------|--------|-------------|
| IDFA without ATT consent | Prohibited | App rejection |
| Device fingerprinting | Prohibited | App rejection |
| Probabilistic matching via device signals | Prohibited | App rejection |
| IDFV for cross-app tracking | Prohibited | App rejection |
| Email hash matching without consent | Prohibited | App rejection |

### Permitted Techniques (First-Party Data)

| Technique | Status | Notes |
|-----------|--------|-------|
| First-party analytics | Allowed | No ATT required |
| Login-based identification | Allowed | User-provided identity |
| Deep link attribution | Allowed | User clicked your link |
| SKAdNetwork | Allowed | Apple's privacy-preserving framework |
| Server-side conversion tracking | Allowed | First-party data only |

---

## Attribution Capability Matrix

### By User Consent State

| Scenario | MTA Capability | Coverage |
|----------|---------------|----------|
| Logged-in users (web + app) | **Full MTA** | Same user_id everywhere |
| ATT-consented users | **Full MTA** | Can use IDFA for cross-app |
| Anonymous app users | **Single-session only** | No cross-session attribution |
| SKAdNetwork | **Single-touch only** | Which ad network drove install |

### Realistic Coverage Expectations

```
┌─────────────────────────────────────────────────────────┐
│                    User Population                       │
├─────────────────────────────────────────────────────────┤
│  Logged-in users:           ~30-40% (varies by app)     │
│  ATT consented:             ~20-25% of remaining        │
│  Anonymous (no attribution): ~35-50%                    │
├─────────────────────────────────────────────────────────┤
│  TOTAL with full MTA:       ~45-55%                     │
└─────────────────────────────────────────────────────────┘
```

---

## Compliant Attribution Strategies

### Strategy 1: First-Party Data (Recommended)

**How it works:**
- User creates account on web (gets `user_id`)
- User downloads iOS app, logs in with same account
- All events tied to `user_id`, not device
- MTA works across web + app because same `user_id`

**Advantages:**
- No ATT consent required
- Full MTA capability
- Works across all platforms
- Future-proof against further privacy changes

**Disadvantages:**
- Only works for logged-in users
- Requires account creation incentive

```swift
// iOS SDK - First-party identification
class MbuzzSDK {
    private var userId: String?
    private var visitorId: String = UUID().uuidString

    func identify(userId: String) {
        self.userId = userId
        // Merge anonymous events to user
        mergeAnonymousEvents()
        // No ATT consent needed
    }

    func track(event: String, properties: [String: Any] = [:]) {
        let payload: [String: Any] = [
            "visitor_id": visitorId,
            "user_id": userId as Any,
            "event": event,
            "properties": properties
        ]
        sendToServer(payload)
    }
}
```

### Strategy 2: Deep Link Attribution

**How it works:**
- User clicks link on web: `https://mbuzz.co/go/campaign123`
- Universal Link opens app with campaign context
- If user logged in, attribute to their journey
- If not logged in, attribute to anonymous session, merge on login

```swift
// AppDelegate.swift
func application(_ app: UIApplication,
                 open url: URL,
                 options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {

    // Extract attribution context from deep link
    if let components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
        let campaign = components.queryItems?.first(where: { $0.name == "campaign" })?.value
        let source = components.queryItems?.first(where: { $0.name == "source" })?.value

        // Store for attribution - no ATT needed
        MbuzzSDK.shared.setDeepLinkContext(
            campaign: campaign,
            source: source
        )
    }
    return true
}
```

**Compliant because:** User explicitly clicked a link you control.

### Strategy 3: SKAdNetwork Integration

Apple's privacy-preserving attribution framework:
- Provides aggregated, delayed conversion data
- No user-level data
- Limited conversion values (0-63)
- 24-48 hour delay minimum

```swift
// Register for SKAdNetwork attribution
import StoreKit

class AppInstallAttribution {
    func registerAppForAdNetworkAttribution() {
        if #available(iOS 11.3, *) {
            SKAdNetwork.registerAppForAdNetworkAttribution()
        }
    }

    func updateConversionValue(_ value: Int) {
        if #available(iOS 14.0, *) {
            SKAdNetwork.updateConversionValue(value)
        }
    }
}
```

**Limitations for mbuzz:**
- Single-touch attribution only (which ad drove install)
- No journey analysis
- Aggregated data (no individual conversions)
- 24-48+ hour delay
- Limited to 64 conversion values

### Strategy 4: Hybrid Web/App Tracking

```
┌─────────────────────────────────────────────────────────┐
│  Web (Full Tracking)         │  App (Limited)          │
│  ─────────────────────       │  ───────────────        │
│  - Cookies work              │  - First-party only     │
│  - Full MTA                  │  - Login-based ID       │
│  - UTM parameters            │  - Deep link context    │
│  - All touchpoints           │  - SKAdNetwork          │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
        Merge on user_id when user logs in
```

---

## iOS SDK Architecture

### What We CAN Collect (Without ATT)

```swift
struct MbuzzEvent {
    // First-party identifiers (we generate)
    let visitorId: String        // Our own anonymous ID (IDFV-based or random)
    let userId: String?          // After login

    // App context (always available)
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let locale: String

    // Event data
    let eventType: String
    let properties: [String: Any]
    let timestamp: Date

    // Attribution context from deep links
    let deepLinkCampaign: String?
    let deepLinkSource: String?
    let deepLinkMedium: String?

    // CANNOT collect without ATT consent
    // let idfa: String?  // Requires ATT
    // No fingerprinting signals
}
```

### SDK Public API

```swift
import MbuzzSDK

// Initialize (AppDelegate or @main)
Mbuzz.configure(apiKey: "sk_live_xxx")

// Track events (always allowed - first-party)
Mbuzz.track("product_viewed", properties: [
    "product_id": "SKU-123",
    "price": 49.99
])

// Track conversions
Mbuzz.conversion("purchase", revenue: 99.99, properties: [
    "order_id": "ORD-456"
])

// Identify user (enables full MTA)
Mbuzz.identify(userId: "user_123", traits: [
    "email": "user@example.com",
    "plan": "premium"
])

// Optional: Request ATT for enhanced attribution
Mbuzz.requestTrackingPermission { authorized in
    if authorized {
        // Can now use IDFA for cross-app attribution
    }
}
```

### Consent Flow

```swift
class MbuzzSDK {
    private var trackingAuthorized = false

    func requestTrackingPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                self.trackingAuthorized = (status == .authorized)
                completion(self.trackingAuthorized)
            }
        } else {
            // Pre-iOS 14: tracking allowed by default
            self.trackingAuthorized = true
            completion(true)
        }
    }

    func getAdvertisingIdentifier() -> String? {
        guard trackingAuthorized else { return nil }

        let idfa = ASIdentifierManager.shared().advertisingIdentifier
        // Check if tracking is limited
        if idfa.uuidString == "00000000-0000-0000-0000-000000000000" {
            return nil
        }
        return idfa.uuidString
    }
}
```

---

## Data Quality & Dashboard Implications

### Attribution Coverage Indicator

The dashboard should show users what percentage of their data has full attribution:

```ruby
# app/helpers/dashboard_helper.rb
def attribution_coverage_indicator(account, date_range)
  stats = Attribution::CoverageService.new(account, date_range).calculate

  {
    full_attribution: stats[:logged_in] + stats[:consented],
    partial_attribution: stats[:deep_link_only],
    no_attribution: stats[:anonymous],
    total_events: stats[:total]
  }
end
```

```erb
<%# Dashboard attribution quality badge %>
<div class="attribution-coverage">
  <div class="flex items-center gap-2">
    <span class="text-sm font-medium">Attribution Coverage</span>
    <span class="badge <%= coverage_badge_class(@coverage_percent) %>">
      <%= number_to_percentage(@coverage_percent, precision: 0) %>
    </span>
  </div>
  <div class="text-xs text-gray-500 mt-1">
    <%= @logged_in_users %> logged-in users,
    <%= @consented_users %> ATT consented
  </div>
</div>
```

### Event Quality Field

```ruby
# app/services/events/ingestion_service.rb
def determine_attribution_quality(event)
  return "full" if event[:idfa].present?
  return "full" if event[:user_id].present?
  return "partial" if event[:deep_link_context].present?
  "anonymous"
end
```

### API Response Enhancement

```json
{
  "event": {
    "id": "evt_abc123",
    "attribution_quality": "full",
    "attribution_source": "user_id"
  }
}
```

---

## Implementation Considerations

### When to Request ATT

**Recommended approach:** Delay ATT prompt until user sees value

```swift
// Don't do this on first launch
// ATTrackingManager.requestTrackingAuthorization { }

// Instead, wait for a meaningful moment
class OnboardingFlow {
    func userCompletedTutorial() {
        // User has seen value, now explain tracking benefit
        showTrackingExplanation {
            Mbuzz.requestTrackingPermission { _ in }
        }
    }
}
```

### Pre-Prompt Explanation

Apps with a pre-prompt explanation see higher opt-in rates:

```swift
func showTrackingExplanation(completion: @escaping () -> Void) {
    let alert = UIAlertController(
        title: "Help Us Improve Your Experience",
        message: "We use this to show you more relevant content and measure how you found us. Your data stays private.",
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
        completion()
    })
    present(alert, animated: true)
}
```

### IDFV as Fallback

IDFV (Identifier for Vendor) is always available without consent:

```swift
let idfv = UIDevice.current.identifierForVendor?.uuidString
```

**Limitations:**
- Resets when user deletes all apps from your company
- Cannot be used for cross-app tracking
- Useful for single-app session continuity

---

## Comparison with Competitors

### How Others Handle iOS Privacy

| Platform | Approach |
|----------|----------|
| **Segment** | First-party focus, IDFA optional, SKAdNetwork integration |
| **Amplitude** | Device ID (IDFV), user ID merge, no IDFA by default |
| **Mixpanel** | Distinct ID system, user ID preferred, IDFA deprecated |
| **Branch** | Probabilistic matching (risky), deep links, SKAdNetwork |
| **AppsFlyer** | SKAdNetwork focus, aggregated data, probabilistic (risky) |

### mbuzz Differentiator

Focus on **server-side, first-party attribution** where iOS SDK is one input:

```
┌─────────────────────────────────────────────────────────┐
│                    mbuzz Server                          │
├─────────────────────────────────────────────────────────┤
│  Web SDK ──────────┐                                    │
│  Server SDK ───────┼──► Attribution Engine ──► Dashboard│
│  iOS SDK ──────────┤     (server-side)                  │
│  Android SDK ──────┘                                    │
└─────────────────────────────────────────────────────────┘
```

The iOS SDK feeds into the same attribution engine, with `user_id` as the unifying key.

---

## Recommended Product Strategy

### 1. Push Authentication Hard

Make login valuable:
- Saved preferences, history
- Cross-device sync
- Personalized experience
- Loyalty/rewards programs

**Higher login rate = higher attribution coverage**

### 2. Rich Deep Linking

Capture maximum context when app opens:

```swift
struct DeepLinkContext {
    let campaign: String?
    let source: String?
    let medium: String?
    let content: String?
    let term: String?
    let referrer: String?
    let timestamp: Date
}
```

### 3. Defer to Web Where Possible

For anonymous users, push them to web flows where tracking is more complete:
- Web checkout instead of in-app
- Web registration flows
- Web for top-of-funnel

### 4. Transparent Coverage Reporting

Show customers what % of users are fully tracked:
- Build trust through honesty
- Help them understand data quality
- Incentivize them to push login

---

## SKAdNetwork Deep Dive

### How SKAdNetwork Works

```
┌─────────────────────────────────────────────────────────┐
│ 1. User sees ad in Ad Network app                        │
│ 2. User taps ad → App Store → Installs your app          │
│ 3. Your app registers with SKAdNetwork                   │
│ 4. Your app updates conversion value (0-63) based on     │
│    user actions over 24-hour windows                     │
│ 5. After delay (24-48h+), Apple sends postback to        │
│    ad network (NOT to you directly)                      │
│ 6. Ad network shares aggregated data with you            │
└─────────────────────────────────────────────────────────┘
```

### What mbuzz Can Do with SKAdNetwork

1. **Ingest postbacks** from ad networks (via API integration)
2. **Show install attribution** by ad network
3. **Cannot** tie specific users to specific ad clicks
4. **Cannot** do multi-touch attribution with SKAdNetwork data

### Implementation

```swift
// In app, update conversion value based on user journey
class SKAdNetworkManager {
    func updateConversionValue(for event: String) {
        guard #available(iOS 14.0, *) else { return }

        let value = conversionValueFor(event: event)
        SKAdNetwork.updateConversionValue(value)
    }

    private func conversionValueFor(event: String) -> Int {
        // Map events to 0-63 value
        switch event {
        case "registration": return 10
        case "add_to_cart": return 20
        case "purchase_small": return 40
        case "purchase_large": return 63
        default: return 1
        }
    }
}
```

---

## Bottom Line

### What iOS Breaks

- Anonymous cross-session attribution
- Cross-app journey tracking (without consent)
- Device fingerprinting
- Probabilistic matching

### What Still Works

- Login-based identification (full MTA)
- ATT-consented users (full MTA, ~20-25%)
- Deep link attribution (partial)
- SKAdNetwork (single-touch, aggregated)
- First-party analytics (always)

### Recommendation

**Build an iOS SDK, but set expectations:**

1. Position iOS SDK as one input to server-side attribution
2. Push `user_id` as the primary identifier (login-based)
3. Use IDFV for single-app session continuity
4. Integrate SKAdNetwork for install attribution
5. Show attribution coverage metrics in dashboard
6. Be transparent about iOS limitations in docs

### Priority

| Priority | Action |
|----------|--------|
| P0 | First-party event tracking (no ATT needed) |
| P0 | Login/identify flow (user_id merge) |
| P1 | Deep link attribution |
| P1 | Attribution quality indicators |
| P2 | SKAdNetwork integration |
| P2 | ATT consent flow (optional enhancement) |

---

## Files to Update When Implementing

| File | Change |
|------|--------|
| `config/sdk_registry.yml` | Add iOS SDK entry |
| `app/models/event.rb` | Add `attribution_quality` field |
| `app/services/events/ingestion_service.rb` | Handle iOS events |
| `app/views/dashboard/*` | Add attribution coverage indicators |
| `lib/specs/sdk_rollout.md` | Add iOS to roadmap |

---

## Open Questions

1. **Should we build iOS SDK at all?** Or focus on web/server SDKs where attribution is more complete?
2. **SKAdNetwork integration effort**: Is it worth the complexity for aggregated data?
3. **Pricing implications**: Should accounts with high iOS traffic (low attribution) pay less?
4. **Documentation strategy**: How prominently do we explain iOS limitations?

---

## Sources

- [Apple App Tracking Transparency](https://developer.apple.com/documentation/apptrackingtransparency)
- [Apple SKAdNetwork](https://developer.apple.com/documentation/storekit/skadnetwork)
- [Apple User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [ATT Opt-in Rates 2024](https://www.appsflyer.com/blog/trends-insights/att-opt-in-rates-higher/)
- [Branch iOS Attribution Guide](https://help.branch.io/developers-hub/docs/ios-advanced-features)
- [Segment iOS Privacy](https://segment.com/docs/connections/sources/catalog/libraries/mobile/ios/ios-privacy/)
