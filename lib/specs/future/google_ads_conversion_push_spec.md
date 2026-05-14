# Google Ads — Conversion Push (Offline Conversion Imports)

**Date:** 2026-05-15
**Status:** Future / Not Scheduled
**Priority:** P2 (post-GA enhancement)

---

## Problem

Today mbuzz pulls daily spend from Google Ads (read-only) and computes attributed ROAS internally. We never push conversions back to Google. This means:

1. Google's Smart Bidding optimizes against the customer's own gtag/pixel conversions, which may be undercounted (ad blockers, ITP, iOS 14+, server-side commerce) or attributed by Google's last-click model rather than mbuzz's multi-touch model.
2. Customers can't ask Google "bid harder on these conversions specifically" using mbuzz's attribution signal.
3. Customers running paid Google traffic to offline conversions (phone calls, in-store, sales-team close) have no clean way to send those back without building their own server-side pipeline.

Several enterprise prospects have asked: "Do you do CAPI for Google like you do for Meta?" Today the answer is no.

## Solution

Add **opt-in, customer-configured offline conversion push** to existing Google Ads connections. Each connection gains a "Push conversions to Google" toggle. When enabled, the customer maps mbuzz conversion types (e.g., `purchase`, `signup`, `lead`) to Google Ads conversion action resource names of their choosing. A new background job fires `UploadClickConversion` API calls when in-scope conversions occur in mbuzz.

**Double-counting prevention is structural, not heuristic.** Google's `UploadClickConversion` API does not dedupe against the customer's existing gtag pixel; the two flows are treated as separate conversion sources. To prevent inflation:
- The UI strongly steers the customer to create a **dedicated** Google Ads conversion action for mbuzz uploads (e.g., "mbuzz: Server Purchase") and links to Google's docs
- The picker shows existing conversion actions but flags any action that is currently primary-for-bidding with a warning
- Customer documentation explains the standard pattern: dedicated action + exclude original pixel action from bidding (or vice versa)

mbuzz never auto-routes to a customer's existing pixel action. The mapping is always explicit and customer-chosen.

## Prerequisites

These must complete before any code lands. They're not optional and not in scope to engineer around.

| # | Prerequisite | Owner | Status |
|---|---|---|---|
| 1 | Amend Google Ads API Center application: Q11 capabilities must include conversion management; Q6 business description must mention conversion uploads | Vlad (no-code) | Not started |
| 2 | Resubmit application, wait for re-approval (typically 3-7 business days) | Google review | Not started |
| 3 | Privacy policy update at `mbuzz.co/privacy`: explicit clause covering server-to-server conversion uploads to customer-connected ad platforms | Vlad | Not started |
| 4 | Customer-facing docs explaining double-count prevention pattern (dedicated conversion action, bidding exclusion) | Vlad | Not started |
| 5 | Google Ads OAuth verification confirmed (per `google_ads_rollout_spec.md` Phase 0) | Vlad | Pending |

Without prereqs 1-2 the developer token can be revoked in a Google audit. Without prereq 3 we're misrepresenting data practices.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| API surface | `UploadClickConversion` (Offline Conversion Imports via gclid) primary; `ConversionAdjustment` for refunds/restatements | Standard server-to-server pattern. Customer's existing gclid capture in `Event::Conversion#properties` is the natural key. |
| Enhanced Conversions for Web (ECW) bolt-on | Phase 2, after OCI works | ECW augments gtag conversions with hashed PII for better matching. Useful but secondary; OCI delivers the primary value first. |
| Enhanced Conversions for Leads (ECL) | Out of scope for v1 | Different surface (hashed PII keys instead of gclid). Add later if a customer needs offline-lead push without gclid. |
| Opt-in granularity | Per-connection toggle + per-conversion-type mapping | A customer with multiple Google accounts may want push on only some; a customer with multiple mbuzz conversion types may want push for purchase but not signup. |
| Default state | OFF for all existing and new connections | Customer must explicitly opt in. No silent behavior change. |
| Dedup against gtag pixel | Customer responsibility, structurally enforced via dedicated conversion action UX | Google's API doesn't dedupe; building heuristic dedup in mbuzz would be brittle and surprising. |
| Idempotency on retry | Use `(gclid, conversion_action_resource_name, conversion_date_time)` as the natural key | Google deduplicates uploads with the same triple. Safe to retry transient failures. |
| Failure mode | Log and skip per-conversion; never block conversion ingestion | Customer's primary data integrity is mbuzz's own conversion record. Push is a secondary artifact. |
| Quota budget | `ApiUsageTracker` already gates at 15k ops/day | Each conversion push is one op. At cap, defer to next day. Reapply for Standard if customers regularly approach the cap. |

## Acceptance Criteria

- [ ] API Center application amended and re-approved before any code review begins
- [ ] Privacy policy updated; legal review if needed
- [ ] `AdPlatformConnection` has `conversion_push_enabled` (boolean) + `conversion_mappings` (jsonb) — keys are mbuzz conversion types, values are Google conversion action resource names
- [ ] `AdPlatforms::Google::ListConversionActionsService` fetches the customer's available conversion actions for the picker
- [ ] `AdPlatforms::Google::UploadConversionService` (ApplicationService) takes a `Event::Conversion` + connection, fires `UploadClickConversion`, handles partial failures
- [ ] `Conversions::PushToAdPlatformsJob` thin wrapper enqueued from the conversion ingestion path, fan-out to all connections with `conversion_push_enabled`
- [ ] Per-connection detail page: toggle + mapping form, with a warning if the chosen action is the customer's primary-for-bidding pixel action
- [ ] Customer docs explain the dedicated-action pattern, link from the mapping form
- [ ] Retry on transient failure (HTTP 5xx, rate limit); permanent failure (invalid gclid, missing conversion action) logged and skipped, surfaced in a connection-health panel
- [ ] No mocks; VCR cassettes against real Google Ads sandbox or live account
- [ ] Cross-account isolation: connection's account_id scopes every read and write
- [ ] `skip_marketing_analytics` on any new controller actions that touch tokens or conversion-action lists

## Out of Scope

- Enhanced Conversions for Leads (ECL) — hashed-PII surface, no gclid. Separate spec if a customer needs it.
- Auto-discovery of customer's gtag conversion actions and "smart" routing — too much footgun risk for double-counting.
- Bid optimization recommendations based on mbuzz attribution data — could be a downstream feature, but the upload API itself is the foundation.
- Push to Microsoft Ads, TikTok, LinkedIn, etc. — each platform's conversion API differs; this spec is Google only.
- Historical backfill of past conversions. v1 pushes new conversions forward; a backfill rake task can come later.

## Implementation Approach (sketch — formalize when scheduled)

Mirror the existing Google adapter shape. Pure parsers + ApplicationService orchestrators + thin job wrapper. New surfaces:

```
app/services/ad_platforms/google/
  list_conversion_actions_service.rb    # Google Ads API: list ConversionActions
  upload_conversion_service.rb          # ApplicationService, UploadClickConversion
  conversion_mapper.rb                  # Maps Event::Conversion → UploadClickConversionRequest

app/jobs/
  conversions/push_to_ad_platforms_job.rb   # Fan-out wrapper, fires for each opted-in connection

app/controllers/accounts/integrations_controller.rb
  # New action: update_conversion_mapping(connection_id)
  # New action: toggle_conversion_push(connection_id)

app/views/accounts/integrations/google_ads_account.html.erb
  # New partial: _conversion_push_panel.html.erb (toggle + mapping form + warning UI)

db migration:
  add_column :ad_platform_connections, :conversion_push_enabled, :boolean, default: false, null: false
  add_column :ad_platform_connections, :conversion_mappings, :jsonb, default: {}, null: false
```

Wire into `Event::Conversion`'s after-create path (existing pattern from analytics push). Honor `conversion_push_enabled` at job time, not enqueue time, so a customer toggling off doesn't leave a backlog of in-flight pushes.

## Open Questions (for when this gets scheduled)

1. Should conversion adjustments (refunds in mbuzz) auto-fire `ConversionAdjustment` API calls to retract or restate the original upload? Strong yes from a data-integrity standpoint, but doubles the API surface. Defer to v1.1 unless a launch customer needs it day one.
2. ECW (Enhanced Conversions for Web) requires customer's existing gtag to send `gtag('set', 'user_data', {...})` with hashed PII. mbuzz doesn't control that script. Provide a JS snippet customers add to their site? Or scope ECW to customers who already use the mbuzz JS SDK and pass us PII?
3. Currency handling. Google requires currency code per upload. mbuzz conversions have a `revenue` and (implicitly) the account's reporting currency. What about multi-currency customers? Adopt Google's per-upload currency override and source from the conversion's metadata if present.
4. Latency budget. Google recommends uploading conversions within 24h. Our job queue is Solid Stack (DB-backed). Acceptable today; verify under load before launch.

## Related

- `lib/specs/google_ads_rollout_spec.md` — read-only GA rollout (prerequisite for any conversion-push customer being able to connect in the first place)
- `lib/specs/platform_api_approvals_spec.md` — Google Ads approval tracker (must reflect amended capabilities post-resubmit)
- `lib/specs/ad_platform_adapter_template_spec.md` — adapter conventions this spec inherits from
- `feedback_no_mocks.md` — testing approach (VCR cassettes only)
- `feedback_global_processor_pattern.md` — usage tracker conventions
