# Custom Channels & Offline Attribution

**Date**: 2026-02-25
**Priority**: P1
**Status**: Draft
**Branch**: `feature/custom-channels`

---

## Summary

Customers see 12 fixed marketing channels. A podcast listener who clicks a show-notes link lands in "referral". A Google Maps click lands in "organic_search". A phone call never appears at all. This spec adds account-level custom channels with pattern-matching rewrite rules, priority ordering, custom chart colours, and phone call CSV upload for offline conversion attribution.

---

## Current State

### Channel System

12 channels defined in `Channels` constant (`app/constants/channels.rb`): `paid_search`, `organic_search`, `paid_social`, `organic_social`, `email`, `display`, `affiliate`, `referral`, `video`, `ai`, `direct`, `other`.

Classification happens once at session creation via `Sessions::ChannelAttributionService` — click IDs first, then UTM medium, UTM source, referrer patterns, finally `direct`. The result is stored on `sessions.channel` and copied to `attribution_credits.channel` when conversions are attributed. Immutable after creation.

### Charts

12 colours hardcoded in `chart_controller.js` (`CHANNEL_COLORS` object). Any channel slug not in the map falls back to gray `#9CA3AF`. No mechanism to inject per-account colours.

### Offline Touchpoints

None. No phone call, in-store, or manual conversion upload. Identity traits (`identities.traits` JSONB) can store phone numbers under arbitrary keys (`phone`, `mobile`, `tel`, etc.) but nothing consumes them.

### Session Landing Page

`sessions.landing_page_host` exists. **No `landing_page_path` column** — path data lives only in event `properties->>'path'`, requiring a JOIN for path-based queries.

### Data Flow (current)

```
SDK → POST /api/v1/sessions
  → Sessions::CreationService
    → ChannelAttributionService → session.channel
    → session saved

Conversion attributed
  → AttributionCredits created → credits.channel = session.channel

Dashboard
  → ByChannelQuery groups credits.channel
  → chart_controller.js renders with CHANNEL_COLORS[channel]
```

---

## Proposed Solution

### Overview

Three interconnected capabilities:

1. **Custom Channels** — Account-level channel definitions with name, colour, priority
2. **Rewrite Rules** — Pattern-matching rules that override standard channel classification on sessions
3. **Phone Call Upload** — CSV import with phone number normalisation and identity matching, creating attributed conversions

### Data Flow (proposed)

```
Session created
  → ChannelAttributionService → session.channel (unchanged)
  → ChannelRules::EvaluationService → session.effective_channel (new, nullable)

Dashboard
  → credits.channel already stores effective value (updated by reprocess)
  → Funnel uses COALESCE(effective_channel, channel)
  → chart_controller.js merges custom colours into CHANNEL_COLORS

Phone CSV uploaded
  → PhoneCalls::CsvImportJob
    → normalise numbers → match to identities → create conversions
    → attribution runs against matched visitor's sessions
```

---

## Data Model

### `custom_channels` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `account_id` | bigint FK | Multi-tenancy, `NOT NULL` |
| `name` | string | Display name: "Podcast", "Local Search" |
| `slug` | string | Identifier: `podcast`, `local_search` |
| `color` | string(7) | Hex: `#FF6B6B` |
| `priority` | integer | Lower = higher priority. 1 evaluated first |
| `is_active` | boolean | Default `true` |
| `created_at` | datetime | |
| `updated_at` | datetime | |

- Unique index: `(account_id, slug)`
- Index: `(account_id, is_active, priority)`
- Prefix: `cch_`
- Slug auto-generated from name via `parameterize(separator: '_')`
- Slug must not collide with `Channels::ALL` (validated)

### `channel_rules` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `account_id` | bigint FK | Multi-tenancy, `NOT NULL` |
| `custom_channel_id` | bigint FK | Parent channel, `NOT NULL` |
| `match_target` | string | What data to match on |
| `match_operator` | string | How to compare |
| `match_field` | string (nullable) | For `query_param`: the param name |
| `match_value` | string (nullable) | Value to match. NULL when operator = `exists` |
| `created_at` | datetime | |
| `updated_at` | datetime | |

- Index: `(custom_channel_id)`
- Prefix: `rule_`

**`match_target` enum:**

| Target | Data Source | Example Use |
|--------|-----------|-------------|
| `landing_page_path` | `sessions.landing_page_path` | `/podcast` landing pages |
| `landing_page_host` | `sessions.landing_page_host` | `events.example.com` subdomain |
| `page_path` | `events.properties->>'path'` | Any page visited during session |
| `query_param` | `events.properties->'query_params'->>match_field` | `google_places_id` present |
| `utm_source` | `sessions.initial_utm->>'utm_source'` | `podcast_app` source |
| `utm_medium` | `sessions.initial_utm->>'utm_medium'` | `podcast` medium |
| `utm_campaign` | `sessions.initial_utm->>'utm_campaign'` | `q1_podcast_launch` campaign |
| `referrer` | `sessions.initial_referrer` | Referrer from specific domain |
| `event_type` | `events.event_type` | `webinar_registered` events |
| `original_channel` | `sessions.channel` | Refine "other" or "referral" |

Session-level targets: `landing_page_path`, `landing_page_host`, `utm_source`, `utm_medium`, `utm_campaign`, `referrer`, `original_channel`.

Event-level targets: `page_path`, `query_param`, `event_type`. A session matches if **any** of its events satisfies the rule.

**`match_operator` enum:**

| Operator | SQL | Notes |
|----------|-----|-------|
| `equals` | `= value` | Exact match, case-insensitive |
| `contains` | `ILIKE '%value%'` | Substring match |
| `starts_with` | `ILIKE 'value%'` | Prefix match |
| `exists` | `IS NOT NULL` | For query_param: key present regardless of value |

### `phone_call_uploads` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `account_id` | bigint FK | |
| `user_id` | bigint FK | Who uploaded |
| `filename` | string | Original CSV filename |
| `status` | integer | Enum: `pending: 0`, `processing: 1`, `completed: 2`, `failed: 3` |
| `total_rows` | integer | |
| `matched_rows` | integer | |
| `unmatched_rows` | integer | |
| `failed_rows` | integer | Rows that couldn't be parsed |
| `error_message` | text (nullable) | On fatal failure |
| `created_at` | datetime | |
| `updated_at` | datetime | |

- Index: `(account_id, created_at)`
- Prefix: `pcu_`

### `phone_calls` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `account_id` | bigint FK | |
| `phone_call_upload_id` | bigint FK | Source upload |
| `phone_number_raw` | string | As uploaded: `(555) 123-4567` |
| `phone_number_normalized` | string (nullable) | E.164: `+15551234567`. NULL if normalisation failed |
| `called_at` | datetime | When the call occurred |
| `duration_seconds` | integer (nullable) | |
| `caller_name` | string (nullable) | |
| `identity_id` | bigint FK (nullable) | Matched identity |
| `visitor_id` | bigint FK (nullable) | Via identity's most recent visitor |
| `conversion_id` | bigint FK (nullable) | Created conversion |
| `match_status` | integer | Enum: `matched: 0`, `unmatched: 1`, `ambiguous: 2`, `invalid_number: 3` |
| `properties` | JSONB | Extra CSV columns |
| `created_at` | datetime | |
| `updated_at` | datetime | |

- Index: `(account_id, phone_number_normalized)`
- Index: `(phone_call_upload_id)`
- Prefix: `pcall_`

### Session Column Additions

Two new columns on `sessions`:

1. **`landing_page_path`** (string, nullable) — Extracted from URL at session creation alongside existing `landing_page_host`. Enables path-based rule matching without event JOINs.

2. **`effective_channel`** (string, nullable) — When set, overrides `channel` for dashboard and attribution. `NULL` means "use standard channel". Preserves original `channel` for audit.

Index: `(account_id, effective_channel)` — partial where `effective_channel IS NOT NULL`.

---

## Channel Rule Evaluation

### Single Session (ingestion-time)

After standard `ChannelAttributionService` sets `channel`:

```
1. Load account's active custom channels, ordered by priority ASC
2. For each custom channel:
   a. Evaluate ALL its rules against the session (OR — any rule = match)
   b. Session-level rules: compare directly
   c. Event-level rules: check if ANY event in the session matches
   d. First matching channel wins → session.effective_channel = channel.slug
   e. STOP — don't evaluate lower-priority channels
3. No match → session.effective_channel = NULL
```

At ingestion time, event-level rules can only check the session's events that exist at that point (typically just the initial page view). Later events won't retroactively re-evaluate. This is acceptable — most rules target landing page or UTM data.

### Batch Reprocess (rule change)

When custom channels or rules are created, updated, or deleted, enqueue `ChannelRules::BatchReprocessJob`:

```ruby
# Step 1: Clear all overrides for account
account.sessions.where.not(effective_channel: nil)
  .update_all(effective_channel: nil)

# Step 2: Apply rules in priority order
account.custom_channels.active.order(:priority).each do |channel|
  matching_ids = ChannelRules::SessionMatcher.new(account, channel).call
  account.sessions.where(id: matching_ids, effective_channel: nil)
    .update_all(effective_channel: channel.slug)
end

# Step 3: Sync attribution credits
account.attribution_credits
  .joins("INNER JOIN sessions ON sessions.id = attribution_credits.session_id")
  .update_all("channel = COALESCE(sessions.effective_channel, sessions.channel)")
```

### Session Matcher SQL

**Session-level rules** (direct column match):

```sql
-- Example: landing_page_path contains "/podcast"
SELECT id FROM sessions
WHERE account_id = :account_id
AND landing_page_path ILIKE '%/podcast%'
```

**Event-level rules** (subquery via events):

```sql
-- Example: query_param "google_places_id" exists
SELECT DISTINCT session_id FROM events
WHERE account_id = :account_id
AND properties->'query_params' ? 'google_places_id'
```

**Multiple rules within one channel** (OR):

```sql
SELECT id FROM sessions WHERE account_id = :account_id AND landing_page_path ILIKE '%/podcast%'
UNION
SELECT DISTINCT session_id FROM events WHERE account_id = :account_id AND event_type = 'podcast_listen'
```

---

## Chart Colour System

### Palette

20 pre-selected colours that don't conflict with the existing 12 standard channel colours:

| Colour | Hex | Name |
|--------|-----|------|
| ![](.) | `#F43F5E` | Rose |
| ![](.) | `#D946EF` | Fuchsia |
| ![](.) | `#0EA5E9` | Sky |
| ![](.) | `#3B82F6` | Blue |
| ![](.) | `#A855F7` | Purple |
| ![](.) | `#475569` | Slate |
| ![](.) | `#D97706` | Amber |
| ![](.) | `#059669` | Emerald |
| ![](.) | `#78716C` | Stone |
| ![](.) | `#EAB308` | Yellow |
| ![](.) | `#FF6B6B` | Coral |
| ![](.) | `#2DD4BF` | Mint |
| ![](.) | `#FB923C` | Peach |
| ![](.) | `#A78BFA` | Lavender |
| ![](.) | `#16A34A` | Forest |
| ![](.) | `#64748B` | Steel |
| ![](.) | `#DC2626` | Crimson |
| ![](.) | `#CA8A04` | Gold |
| ![](.) | `#2563EB` | Sapphire |
| ![](.) | `#65A30D` | Chartreuse |

Settings UI presents these as a selectable grid. First unused colour auto-selected as default.

### Chart Controller Integration

Server passes custom colours via data attribute:

```erb
<div data-controller="chart"
     data-chart-custom-colors-value="<%= @custom_channel_colors.to_json %>">
```

Chart controller merges at lookup time:

```javascript
static values = {
  // ... existing values
  customColors: { type: Object, default: {} }
}

getColor(channel) {
  return this.customColorsValue[channel]
    || CHANNEL_COLORS[channel]
    || "#9CA3AF"
}
```

Custom colours take precedence over standard. All chart renderers (`renderBarChart`, `renderLineChart`, `renderStackedBarChart`, `renderSmilingCurve`) call `getColor()` instead of direct lookup.

### Display Names

Custom channel slugs are stored as `snake_case`. Display formatting:

```ruby
# "local_search" → "Local Search"
# "podcast" → "Podcast"
channel_slug.titleize
```

Standard channels keep their existing display logic. Custom channels detected by exclusion from `Channels::ALL`.

---

## Phone Number Normalisation

### Algorithm

```
Input: raw phone string from CSV or identity traits

1. Strip all characters except digits and leading +
2. Classify:
   +N...          (starts with +, 11-15 digits total)  → E.164, keep as-is
   1XXXXXXXXXX    (11 digits starting with 1)           → +1XXXXXXXXXX
   XXXXXXXXXX     (exactly 10 digits)                   → +1XXXXXXXXXX (assume US)
   0XXXXXXXXX     (starts with 0, 10-11 digits)         → strip leading 0, prepend +country
   Other          (< 10 or > 15 digits after strip)     → nil (invalid)

3. Validate: result matches /^\+\d{10,15}$/
4. Return normalised string or nil
```

### Service

```ruby
module PhoneNumbers
  class NormalizationService
    PHONE_REGEX = /^\+\d{10,15}$/

    def initialize(raw)
      @raw = raw.to_s.strip
    end

    def call
      return nil if raw.blank?
      normalized = strip_and_classify
      normalized&.match?(PHONE_REGEX) ? normalized : nil
    end

    private

    attr_reader :raw

    def strip_and_classify
      digits = raw.gsub(/[^\d+]/, "")
      return digits if digits.start_with?("+") && digits.length.between?(11, 16)
      digits = digits.delete("+")
      return nil if digits.length < 10 || digits.length > 15
      return "+#{digits}" if digits.length == 11 && digits.start_with?("1")
      return "+1#{digits}" if digits.length == 10
      "+#{digits}"
    end
  end
end
```

No external gem. Handles US and basic international formats. Out of scope: per-country validation rules (would need `phonelib` gem).

### Identity Phone Lookup

Predefined trait keys to search:

```ruby
PHONE_TRAIT_KEYS = %w[phone phone_number mobile telephone cell tel work_phone home_phone].freeze
```

Build a normalised lookup hash for the account:

```ruby
def build_phone_lookup(account)
  lookup = {}  # normalised_phone → identity

  identities = account.identities.where(
    "traits ?| array[:keys]",
    keys: PHONE_TRAIT_KEYS
  )

  identities.find_each do |identity|
    PHONE_TRAIT_KEYS.each do |key|
      raw = identity.traits&.dig(key)
      next unless raw.present?
      normalized = PhoneNumbers::NormalizationService.new(raw).call
      next unless normalized
      lookup[normalized] ||= identity  # first match wins (most recently identified)
    end
  end

  lookup
end
```

### Matching Precedence

When multiple identities share the same normalised phone number:

1. Query identities ordered by `last_identified_at DESC`
2. First match wins
3. Phone call marked `match_status: :ambiguous` if > 1 identity matches (still attributed to first)

---

## Phone Call Upload Flow

### CSV Format

Required columns:
- `phone_number` — any format, will be normalised
- `called_at` — ISO 8601 or common date formats (`YYYY-MM-DD HH:MM`, `MM/DD/YYYY`, etc.)

Optional columns:
- `duration` — seconds (integer)
- `caller_name` — string
- Any additional columns → stored in `phone_calls.properties` JSONB

### Processing Pipeline

```
1. User uploads CSV via Settings → Phone Calls
2. Create PhoneCallUpload (status: pending)
3. Enqueue PhoneCalls::CsvImportJob

Job:
4. Update status → processing
5. Parse CSV headers, validate required columns
6. Build identity phone lookup for account
7. For each row:
   a. Parse called_at, phone_number, optional fields
   b. Normalise phone number
   c. If normalisation fails → match_status: invalid_number
   d. Look up identity in hash
   e. If found → match_status: matched, set identity_id + visitor_id (identity's most recent visitor)
   f. If not found → match_status: unmatched
   g. If ambiguous → match_status: ambiguous, use first identity
   h. Create PhoneCall record
8. For each matched phone call:
   a. Create Conversion (type: "phone_call", visitor_id, converted_at: called_at)
   b. Attribution runs → credits distributed across visitor's journey sessions
   c. Store conversion_id on phone_call record
9. Update upload totals (matched, unmatched, failed)
10. Update status → completed (or failed on fatal error)
```

### Conversion Creation

Matched phone calls create conversions:

```ruby
{
  account_id: account.id,
  visitor_id: phone_call.visitor_id,
  conversion_type: "phone_call",
  converted_at: phone_call.called_at,
  revenue: nil,  # phone calls don't carry revenue by default
  properties: { phone_number: phone_call.phone_number_normalized, duration: phone_call.duration_seconds }
}
```

Attribution distributes credit across the matched visitor's journey sessions using the account's active attribution model. The channels on those credits are the standard (or effective, if custom rules apply) channels that drove the visitor's sessions. The phone call itself is not a channel — it's the conversion event.

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Override column | `effective_channel` (nullable) on sessions | Preserves original `channel` for audit. NULL = no override. Reversible |
| Rule application | Materialized (batch reprocess on change) + real-time at ingestion | No per-query overhead. Dashboard uses pre-computed values |
| Rule logic within channel | OR (any rule matches = channel matches) | Intuitive: "catch /podcast OR utm_source=podcast" |
| Priority scope | On `custom_channel`, not `channel_rule` | Channels compete for sessions. Rules within a channel cooperate |
| Phone normalisation | In-house service, no gem | Simple strip-and-classify handles US + basic international. `phonelib` later if needed |
| Phone trait discovery | Predefined key list | Covers common conventions. Extensible without schema change |
| Phone calls in attribution | Conversion, not channel | Phone call = conversion event. Channel = what drove the web sessions before the call |
| Colour storage | Hex string per custom channel | Simple, CSS-native, no palette table needed |
| Colour palette | 20 pre-selected options | Visually distinct from standard 12. Avoids colour theory decisions for users |
| Landing page path | New session column | Enables efficient path-based matching. Extracted at session creation alongside existing host |
| Slug validation | Must not collide with `Channels::ALL` | Prevents confusion between standard and custom channels in queries |
| Credit sync | Update `credits.channel` directly from session | No new column on credits. Single UPDATE statement. Credit amounts unchanged — only the channel bucket changes |
| Batch reprocess | Background job, clear-then-apply | Idempotent. Handles rule additions, changes, and deletions uniformly |

---

## All States

### Channel Rules

| # | State | Expected Behaviour |
|---|-------|--------------------|
| 1 | No custom channels | Standard 12 channels, `effective_channel` NULL everywhere. Zero overhead |
| 2 | Single rule, single channel | Matching sessions get `effective_channel`. Credits updated. Chart shows custom channel + custom colour |
| 3 | Multiple rules, one channel (OR) | Session matching **any** rule gets the channel |
| 4 | Multiple channels, overlap | Session matching rules from two channels → lowest `priority` number wins |
| 5 | Rule matches zero sessions | Channel appears in settings but not in charts. No data, no error |
| 6 | Rule deactivated | Reprocess clears `effective_channel` for affected sessions. Standard channel restored |
| 7 | Custom channel deleted | Reprocess clears overrides. Attribution credits reverted. Historical conversion CSVs already exported retain the old channel label |
| 8 | New session matches rule (real-time) | `effective_channel` set at ingestion. Credits created with effective channel when conversion comes |
| 9 | Event-level rule at ingestion | Only events that exist at session creation time are evaluated. Subsequent events don't retroactively trigger. Acceptable: most rules target landing page / UTM |
| 10 | Slug conflicts with standard channel | Validation rejects. User must choose different name |
| 11 | Very broad rule (matches thousands) | Batch reprocess runs in background. Job handles pagination. No timeout |
| 12 | Account has no sessions yet | Rules saved, evaluated when first session arrives |

### Phone Calls

| # | State | Expected Behaviour |
|---|-------|--------------------|
| 13 | All calls matched | 100% match rate. Conversions created for all. Summary shows green |
| 14 | Partial match | Matched → conversions. Unmatched → stored, visible in upload detail |
| 15 | Zero matches | No conversions. Upload completed with 0% match rate. User prompted to check identify calls |
| 16 | Invalid phone numbers | `match_status: invalid_number`. Counted in `failed_rows`. Row not discarded |
| 17 | Ambiguous match (same phone, multiple identities) | Uses most recently identified. `match_status: ambiguous`. Still creates conversion |
| 18 | Identity has no visitors | Match found but no visitor to attribute. Conversion created with `visitor_id` NULL. Shows in funnel but no attribution credits |
| 19 | Identity has multiple visitors | Uses most recent visitor (by `last_seen_at`) |
| 20 | Duplicate phone number in CSV | Each row processed independently. Multiple conversions created (user's intent) |
| 21 | Missing `called_at` column | Upload fails validation before processing. Status: failed. Error message explains |
| 22 | Malformed CSV | Fatal: status failed. Per-row: skip and count in `failed_rows` |
| 23 | Upload deleted | Phone calls + associated conversions cascade-deleted. Attribution credits for those conversions removed |

---

## Implementation Tasks

### Phase 1: Data Model & Core Services

- [ ] 1.1 Migration: create `custom_channels` table
- [ ] 1.2 Migration: create `channel_rules` table
- [ ] 1.3 Migration: add `landing_page_path` to sessions
- [ ] 1.4 Migration: add `effective_channel` to sessions
- [ ] 1.5 `CustomChannel` model + concerns (validations, relationships, scopes, slug generation)
- [ ] 1.6 `ChannelRule` model + concerns (validations, relationships, match_target/operator enums)
- [ ] 1.7 Update `Sessions::CreationService` to extract and store `landing_page_path` from URL
- [ ] 1.8 `ChannelRules::EvaluationService` — evaluates rules against one session, returns custom channel slug or nil
- [ ] 1.9 `ChannelRules::SessionMatcher` — builds SQL for a custom channel's rules, returns matching session IDs
- [ ] 1.10 `ChannelRules::BatchReprocessService` — clears, applies in priority order, syncs credits
- [ ] 1.11 `ChannelRules::BatchReprocessJob` — thin wrapper, enqueued on rule changes
- [ ] 1.12 Wire `EvaluationService` into `Sessions::CreationService` after standard attribution
- [ ] 1.13 Tests: models, evaluation service, session matcher, batch reprocess, creation integration

### Phase 2: Dashboard Integration

- [ ] 2.1 Update funnel session queries to use `COALESCE(effective_channel, channel)` as channel
- [ ] 2.2 `attribution_credits.channel` already stores effective value after reprocess — verify `ByChannelQuery` needs no change
- [ ] 2.3 Build helper to load account's custom channel colour map (`{ slug => hex }`)
- [ ] 2.4 Pass custom colour map to chart views via data attribute
- [ ] 2.5 Update `chart_controller.js`: add `customColors` value, `getColor()` method, replace all direct `CHANNEL_COLORS` lookups
- [ ] 2.6 Custom channel display name formatting (slug → title case)
- [ ] 2.7 Tests: dashboard with custom channels renders correct colours and labels

### Phase 3: Settings UI — Custom Channels

- [ ] 3.1 `Accounts::CustomChannelsController` — index, new, create, edit, update, destroy, reprocess
- [ ] 3.2 Routes: `resources :custom_channels` under accounts namespace + `post :reprocess` member
- [ ] 3.3 Index view: list with priority numbers, colour dots, rule counts, active toggle
- [ ] 3.4 Form view: name input, colour palette picker, nested rules (Turbo Frame for add/remove)
- [ ] 3.5 Rule partial: match_target dropdown, match_operator dropdown, match_field (conditional on target), match_value input
- [ ] 3.6 Priority reordering: up/down arrows (Turbo Stream PATCH for position swap)
- [ ] 3.7 "Reprocess" button on index — enqueues job, shows flash with status
- [ ] 3.8 Add "Custom Channels" link to settings navigation
- [ ] 3.9 Tests: controller CRUD, system test for create + reorder

### Phase 4: Phone Call Upload

- [ ] 4.1 Migration: create `phone_call_uploads` table
- [ ] 4.2 Migration: create `phone_calls` table
- [ ] 4.3 `PhoneCallUpload` model + `PhoneCall` model + concerns
- [ ] 4.4 `PhoneNumbers::NormalizationService`
- [ ] 4.5 `PhoneCalls::IdentityMatchService` — builds normalised phone lookup for account
- [ ] 4.6 `PhoneCalls::CsvImportService` — parses CSV, normalises, matches, creates records
- [ ] 4.7 `PhoneCalls::ConversionCreationService` — creates conversions for matched calls, triggers attribution
- [ ] 4.8 `PhoneCalls::CsvImportJob` — orchestrates import pipeline
- [ ] 4.9 `Accounts::PhoneCallUploadsController` — new, create, show (results), destroy
- [ ] 4.10 Upload view: CSV file input, format instructions
- [ ] 4.11 Results view: match summary (matched/unmatched/failed counts), table of calls with status
- [ ] 4.12 Tests: normalisation (all format variations), identity matching, CSV import, conversion creation

### Phase 5: Polish & Ship

- [ ] 5.1 Full test suite pass — zero regressions
- [ ] 5.2 Manual QA: create channels, apply rules, verify charts, upload phone CSV
- [ ] 5.3 Update `PRODUCT.md`
- [ ] 5.4 Update `BUSINESS_RULES.md`

---

## Testing Strategy

### Unit Tests

| # | Test | Service |
|---|------|---------|
| 1 | Rule matches landing_page_path with each operator | `ChannelRules::EvaluationService` |
| 2 | Rule matches UTM source/medium/campaign | `ChannelRules::EvaluationService` |
| 3 | Rule matches event page_path (session-level via event) | `ChannelRules::EvaluationService` |
| 4 | Rule matches query_param existence (`exists` operator) | `ChannelRules::EvaluationService` |
| 5 | Rule matches event_type | `ChannelRules::EvaluationService` |
| 6 | Multiple rules OR within channel | `ChannelRules::EvaluationService` |
| 7 | No rules match → returns nil | `ChannelRules::EvaluationService` |
| 8 | Inactive channel skipped | `ChannelRules::EvaluationService` |
| 9 | Priority ordering: lower number wins | `ChannelRules::BatchReprocessService` |
| 10 | Batch clears stale effective_channel | `ChannelRules::BatchReprocessService` |
| 11 | Attribution credits updated after reprocess | `ChannelRules::BatchReprocessService` |
| 12 | Session creation sets effective_channel | `Sessions::CreationService` integration |
| 13 | Landing page path extracted from URL | `Sessions::CreationService` |
| 14 | Slug uniqueness within account | `CustomChannel` model |
| 15 | Slug rejects standard channel names | `CustomChannel` model |
| 16 | US phone: `(555) 123-4567` → `+15551234567` | `PhoneNumbers::NormalizationService` |
| 17 | US phone: `555-123-4567` → `+15551234567` | `PhoneNumbers::NormalizationService` |
| 18 | International: `+44 20 7946 0958` → `+442079460958` | `PhoneNumbers::NormalizationService` |
| 19 | Already E.164: `+15551234567` → `+15551234567` | `PhoneNumbers::NormalizationService` |
| 20 | Invalid: `123` → nil | `PhoneNumbers::NormalizationService` |
| 21 | Identity match via traits.phone | `PhoneCalls::IdentityMatchService` |
| 22 | Identity match via traits.mobile (alternate key) | `PhoneCalls::IdentityMatchService` |
| 23 | No match → unmatched status | `PhoneCalls::IdentityMatchService` |
| 24 | Ambiguous match → uses most recent identity | `PhoneCalls::IdentityMatchService` |
| 25 | CSV import creates phone_calls + conversions | `PhoneCalls::CsvImportService` |
| 26 | CSV with missing required column → fails | `PhoneCalls::CsvImportService` |
| 27 | Cross-account isolation for all services | All services |

### Integration Tests

| # | Test |
|---|------|
| 1 | Create custom channel + rule → new session gets effective_channel → dashboard shows custom channel with colour |
| 2 | Batch reprocess: create rule → existing sessions updated → credits reflect new channel |
| 3 | Priority conflict: two channels match same session → higher priority wins |
| 4 | Delete custom channel → sessions revert to standard channel |
| 5 | Phone CSV upload → matched calls appear as conversions in dashboard |
| 6 | Phone upload with no matches → zero conversions, upload shows results |

### Manual QA

- [ ] Create "Podcast" channel with rule: landing_page_path contains `/podcast`
- [ ] Create "Local Search" channel with rule: query_param `google_places_id` exists
- [ ] Verify priority: Podcast at 1, Local Search at 2. Session matching both → Podcast
- [ ] Verify charts: custom channels show with correct colours, legend labels correct
- [ ] Upload phone call CSV with mixed formats (US, international, invalid)
- [ ] Verify matched calls create conversions visible in funnel
- [ ] Verify unmatched calls visible in upload detail
- [ ] Deactivate channel → reprocess → sessions revert
- [ ] Delete upload → phone calls and conversions removed

---

## Definition of Done

- [ ] Custom channels persist with name, slug, colour, priority
- [ ] Rules evaluate correctly for all match_target + match_operator combinations
- [ ] Batch reprocess updates sessions and credits idempotently
- [ ] New sessions at ingestion respect active rules
- [ ] Dashboard charts display custom channels with correct custom colours
- [ ] Priority ordering resolves conflicts deterministically
- [ ] Phone number normalisation handles US and basic international formats
- [ ] Phone CSV upload matches calls to identities via trait phone numbers
- [ ] Matched phone calls create conversions with proper attribution
- [ ] All queries scoped to account (multi-tenancy)
- [ ] No raw database IDs exposed (prefixed_ids on all new models)
- [ ] Settings UI for channel management and phone upload
- [ ] Full test suite passes, zero regressions
- [ ] `PRODUCT.md` and `BUSINESS_RULES.md` updated

---

## Out of Scope

- **Regex match operator** — performance risk with user-supplied patterns. Revisit if customers need it
- **Real-time rule preview** — "Show me what would match" before saving. Future enhancement
- **Retroactive event-level evaluation** — events added after session creation don't re-trigger rule evaluation
- **Phone number library (phonelib/libphonenumber)** — in-house normaliser covers common cases. Add gem when international edge cases justify it
- **Phone call recording/audio** — only metadata (number, timestamp, duration)
- **Phone call deduplication** — same number, same day = multiple records. User's responsibility
- **Historical backfill of `landing_page_path`** — only populated for new sessions after migration
- **Custom channel API** — settings UI only. API endpoint if customers request it
- **Channel grouping/hierarchy** — custom channels are flat, same level as standard channels
- **Multiple colours per channel** — one hex per channel. No gradients
- **Rule import/export** — manual entry only for now
- **Webhooks for phone match results** — UI-only feedback
- **International phone validation per country** — would require `phonelib` gem
- **Auto-detect phone trait keys** — uses predefined `PHONE_TRAIT_KEYS` list
