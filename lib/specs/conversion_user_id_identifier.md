# Accept user_id alone on /conversions

**Date:** 2026-05-26
**Status:** Ready
**Branch:** `feature/conversion-user-id-identifier`

## Problem

Server-side conversion tracking — the whole pitch of the SDK ecosystem — fails for any conversion that lacks a `visitor_id`. Today `Conversions::TrackingService` requires `event_id || visitor_id`; `user_id` is permitted but used only as a lookup key for stamping an existing `Identity` *after* a visitor is already resolved.

This breaks two real cases the SDKs already attempt:

1. **WooCommerce guest checkouts.** The new `mbuzz-wp` plugin's `Integrations::WooCommerce` hook fires `conversion('purchase', user_id: billing_email, ...)` for guest orders. Backend returns `422 "event_id or visitor_id is required"`. The integration silently drops the conversion.
2. **Logged-in checkouts where the visitor cookie was stripped** (privacy browsers, consent walls, REST/cURL flows). The SDK passes a `user_id`; backend rejects.

Every SDK already passes `user_id` (PHP `Mbuzz::conversion(user_id: ...)`, Ruby `Client.conversion(user_id:)`, Python, Node, sGTM — confirmed by audit on 2026-05-26). **The bottleneck is the backend, not the SDKs.** Changing the backend means zero SDK changes are needed.

## Solution

Extend `Conversions::TrackingService` to accept `user_id` as a sufficient identifier. When only `user_id` is provided, resolve a visitor by walking the existing `Identity` graph; create both if missing.

Mirrors the pattern already used by `Identities::IdentificationService#identity` (`account.identities.find_or_create_by!(external_id: user_id)`) — no new abstractions.

### Resolution chain (after)

```
resolved_visitor =
  event.visitor                         # event-based conversion (unchanged)
  || find_visitor_by_id                 # visitor_id from cookie       (unchanged)
  || find_visitor_by_fingerprint        # ip+ua 30s window             (unchanged)
  || find_visitor_via_user_id           # NEW — user_id → identity → visitor
```

`find_visitor_via_user_id`:
1. `find_or_create_by!(external_id: user_id)` on `account.identities` (same Identity row IdentificationService would build).
2. Return the identity's most-recently-updated visitor if one exists.
3. Otherwise create a new visitor scoped to the identity (`SecureRandom.hex(32)` visitor_id, `is_test` propagated from the API key).

When the same user later visits with a cookie, the existing `Identities::IdentificationService` already merges the cookie's visitor onto the identity and triggers `Conversions::ReattributionJob` for prior conversions — so a conversion captured cookielessly today gets reattributed to the cookied journey tomorrow without any new code.

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Where to put visitor creation | Inside TrackingService | Single-purpose, doesn't touch IdentificationService. If reused elsewhere later, extract then. |
| New row per cookieless conversion vs find-or-create per identity | Per identity (find most recent first) | Avoids accumulating dust. Identity.visitors.order(updated_at: :desc).first gives the canonical "this user's visitor" without a deterministic visitor_id scheme. |
| `resolved_identity` (used for `identity_id` on the conversion) | Reuse `@persisted_identity` if the visitor fallback fired, otherwise `find_by` (existing behavior) | No behavior change for the existing cookied path. Identity auto-creates only when actually needed for visitor resolution. |
| `identifier` param on conversion endpoint | Leave alone; do not permit | `identifier` is redundant with `user_id` — backend events endpoint already treats them identically. Adding it here introduces a second way to do the same thing. SDK-level deprecation can follow separately. |
| Fingerprint fallback ordering | Still before user_id | Fingerprint is a tighter signal (same IP+UA, 30s) than user_id (which can be re-used across devices). Keep it earlier in the chain. |

## Acceptance Criteria

- [ ] Conversion with only `user_id` (no event_id, no visitor_id, no fingerprint match) succeeds and creates an Identity + Visitor.
- [ ] Conversion with `user_id` when an Identity already exists reuses it; reuses the identity's most-recent Visitor if one exists.
- [ ] Conversion with `visitor_id` AND `user_id` still resolves via `visitor_id` (unchanged behavior); `identity_id` stamping unchanged.
- [ ] `has_identifier?` validation error message updated: "event_id, visitor_id, or user_id is required".
- [ ] `is_test` flag propagates from the API key to both the new Identity and the new Visitor.
- [ ] `Conversions::ReattributionJob` still queues correctly when a later cookied visit links the same identity (no regression).
- [ ] Existing 100% test pass rate on `Conversions::TrackingServiceTest`.

## Out of Scope

- Permitting `identifier` on the conversions endpoint. Redundant with `user_id`; SDK-level deprecation tracked separately.
- Adding `identifier:` kwarg to mbuzz-ruby / mbuzz-sgtm. Their `user_id` paths already work post-change.
- WP plugin update — covered separately in mbuzz-wp; will land alongside this PR.
- Hashing of email-as-user_id at rest. Customers already pass raw external IDs (sometimes emails, sometimes numeric) — treating user_id consistently here is the right call; PII at rest is a separate spec.

## Out of scope but worth noting

The sGTM template (`mbuzzco/mbuzz-sgtm`) doesn't send `user_id` on its conversion payload even when the GTM tag has one configured. Separate ticket — small fix.
