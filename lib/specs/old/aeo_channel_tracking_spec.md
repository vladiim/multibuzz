# AEO Channel Tracking Specification

**Date:** 2026-01-30
**Priority:** P1
**Status:** Complete
**Branch:** `feature/e1s4-content`

---

## Summary

AI answer engines (ChatGPT, Perplexity, Claude, Gemini, etc.) are a growing traffic source that our channel attribution system doesn't track. Traffic from these platforms currently falls through to `referral` or `direct` -- invisible to customers trying to understand their AEO (Answer Engine Optimization) performance. This spec adds an `ai` channel and recognizes AI answer engine referrers.

---

## Current State

### Channel Attribution Flow

`Sessions::ChannelAttributionService` classifies traffic using a GA4-aligned hierarchy:

```
1. Click identifiers (gclid, fbclid, etc.)
2. Google Places (plcid in utm_term)
3. UTM medium pattern matching
4. UTM source pattern matching
5. Internal referrer check
6. Referrer database lookup (ReferrerSources::LookupService)
7. Referrer regex fallback (SEARCH_ENGINES, SOCIAL_NETWORKS, VIDEO_PLATFORMS)
8. Direct (ultimate fallback)
```

Source: `app/services/sessions/channel_attribution_service.rb`

### What Happens to AI Traffic Today

| Source | Referrer Domain | Current Classification | Why |
|--------|----------------|----------------------|-----|
| ChatGPT | `chatgpt.com` | `referral` | Not in any pattern or lookup |
| Perplexity | `perplexity.ai` | `referral` | Not in any pattern or lookup |
| Claude | `claude.ai` | `referral` | Not in any pattern or lookup |
| Gemini | `gemini.google.com` | `organic_search` | Matches `google` in `SEARCH_ENGINES` regex |
| Google AI Overview | `google.com` | `organic_search` | Same domain as regular Google search |
| Bing Copilot | `bing.com` | `organic_search` | Matches `bing` in `SEARCH_ENGINES` regex |
| Meta AI | `meta.ai` | `referral` | Not in any pattern or lookup |

The worst case is Gemini -- it gets lumped with organic Google search, making it impossible to separate AI-driven from traditional search traffic.

### Referrer Sources Database

The `referrer_sources` table stores known domains with their medium (search, social, etc.). `ReferrerSources::SyncService` pulls from Matomo and Snowplow upstream sources. ChatGPT and Perplexity exist in the Matomo search engine list, but are categorized as `search` -- not as a distinct AI medium.

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/constants/channels.rb` | Channel constants + regex patterns | Add `AI` channel + `AI_ENGINES` pattern |
| `app/services/sessions/channel_attribution_service.rb` | Classification hierarchy | Add AI medium/referrer mapping |
| `app/constants/referrer_sources/mediums.rb` | Referrer source medium types | Add `AI` medium |
| `app/services/referrer_sources/lookup_service.rb` | Domain-to-source lookup | No changes (already generic) |

---

## Proposed Solution

Add a new `ai` channel that captures traffic from AI answer engines. The approach is minimal and consistent with existing patterns -- no new services, no new tables, just expanding the existing classification vocabulary.

### Data Flow (Proposed)

```
Referrer: chatgpt.com
  → LookupService finds referrer_source with medium: "ai"
  → MEDIUM_TO_CHANNEL maps "ai" → Channels::AI
  → Session.channel = "ai"

Referrer: gemini.google.com
  → LookupService finds referrer_source for "gemini.google.com" with medium: "ai"
  → Matched BEFORE falling through to regex (which would match "google")
  → Session.channel = "ai"

UTM: utm_medium=ai, utm_source=chatgpt
  → UTM_MEDIUM_PATTERNS matches /^ai$/i → Channels::AI
  → Session.channel = "ai"
```

### AI Engine Domains

| Domain | Source Name | Notes |
|--------|-----------|-------|
| `chatgpt.com` | ChatGPT | OpenAI's chat interface |
| `chat.openai.com` | ChatGPT | Legacy domain |
| `perplexity.ai` | Perplexity | AI search engine |
| `claude.ai` | Claude | Anthropic's chat interface |
| `gemini.google.com` | Gemini | Google's AI (must match before `google.com`) |
| `copilot.microsoft.com` | Copilot | Microsoft's AI (must match before `bing.com`) |
| `meta.ai` | Meta AI | Meta's AI assistant |
| `grok.x.ai` | Grok | X/Twitter's AI |
| `you.com` | You.com | AI search engine |
| `phind.com` | Phind | Developer AI search |
| `kagi.com` | Kagi | Privacy-focused AI search |

### Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| New channel vs subchannel of search | New `ai` channel | AI engines are a fundamentally different acquisition path. Customers need to see AEO performance separately from SEO. |
| Database seeds vs code constants | Database seeds in `referrer_sources` | Consistent with existing pattern. New domains can be added without deploys. |
| Handle `gemini.google.com` | Exact subdomain match in `referrer_sources` | `LookupService` checks exact domain before root domain, so `gemini.google.com` resolves before `google.com` falls to regex. |
| UTM medium support | Add `ai` to `UTM_MEDIUM_PATTERNS` | Forward-looking: marketers will start tagging AI traffic explicitly. |
| Regex fallback pattern | Add `AI_ENGINES` regex to `Channels` | Safety net for domains not yet in the database. |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | Referrer is `chatgpt.com` | Channel = `ai`, source = ChatGPT |
| Subdomain match | Referrer is `gemini.google.com` | Channel = `ai` (not `organic_search`) |
| UTM tagged | `utm_medium=ai&utm_source=perplexity` | Channel = `ai` |
| UTM overrides referrer | `utm_medium=cpc&utm_source=google`, referrer `chatgpt.com` | Channel = `paid_search` (UTM takes priority) |
| Unknown AI engine | New AI engine not in DB or regex | Falls through to `referral` (same as today) |
| Empty referrer sources DB | Sync hasn't run | Regex fallback catches major AI engines |
| Google AI Overview | Referrer is `google.com` with no distinct signal | Channel = `organic_search` (indistinguishable without click-level data) |

---

## Implementation Tasks

### Phase 1: Channel + Constants

- [x] **1.1** Add `AI = "ai"` to `Channels` constant and `ALL` array
- [x] **1.2** Add `AI_ENGINES` regex to `Channels` (chatgpt, perplexity, claude, gemini, copilot, meta\.ai, grok, phind, you\.com, kagi)
- [x] **1.3** Add `AI = "ai"` to `ReferrerSources::Mediums` constant and `ALL` array
- [x] **1.4** Write tests

### Phase 2: Attribution Service

- [x] **2.1** Add `ai` medium pattern to `UTM_MEDIUM_PATTERNS` in `ChannelAttributionService`
- [x] **2.2** Add `Mediums::AI => Channels::AI` to `MEDIUM_TO_CHANNEL` mapping
- [x] **2.3** Add `AI_ENGINES` to `REFERRER_DOMAIN_PATTERNS` fallback
- [x] **2.4** Write tests for all AI referrer scenarios

### Phase 3: Seed Data

- [x] **3.1** Create seed/migration to insert AI engine domains into `referrer_sources` table with `medium: "ai"` and `data_origin: "manual"`
- [x] **3.2** Verify `LookupService` resolves `gemini.google.com` to `ai` (not falling through to `google.com` → `search`)
- [x] **3.3** Write tests

### Phase 4: Dashboard

- [x] **4.1** Add `ai` channel to any dashboard channel lists, color mappings, or display labels
- [x] **4.2** Verify channel filter includes `ai`
- [ ] **4.3** Manual QA on dev (pending deploy)

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| ChatGPT referrer → ai channel | `test/services/sessions/channel_attribution_service_test.rb` | Referrer lookup path |
| Perplexity referrer → ai channel | `test/services/sessions/channel_attribution_service_test.rb` | Referrer lookup path |
| Gemini referrer → ai (not organic_search) | `test/services/sessions/channel_attribution_service_test.rb` | Subdomain takes priority over root domain regex |
| utm_medium=ai → ai channel | `test/services/sessions/channel_attribution_service_test.rb` | UTM medium pattern |
| Regex fallback for AI domains | `test/services/sessions/channel_attribution_service_test.rb` | Pattern matching without DB |
| AI medium in MEDIUM_TO_CHANNEL | `test/services/sessions/channel_attribution_service_test.rb` | Mapping constant |

### Manual QA

1. Run `ReferrerSources::SyncService` or seed AI domains manually
2. Create a session with referrer `https://chatgpt.com/`
3. Verify session.channel = `ai`
4. Check dashboard channel breakdown shows "AI" with correct count
5. Verify `gemini.google.com` referrer does NOT classify as `organic_search`

---

## Definition of Done

- [x] All tasks completed
- [x] Tests pass (unit + integration) — 2279 tests, 0 failures
- [ ] Manual QA on dev (pending deploy)
- [x] No regressions in existing channel classification
- [x] Dashboard displays AI channel correctly (color: cyan #06B6D4, filter included)
- [x] Spec updated with final state

---

## Out of Scope

- **Google AI Overviews**: Indistinguishable from regular Google organic at the referrer level. No reliable signal exists today. Revisit if Google adds a distinct referrer or click parameter.
- **Paid AI channels**: No ad platforms exist for AI engines yet. When they do, we'll need `paid_ai` (similar to `paid_search` / `organic_search` split).
- **Backfilling historical sessions**: Existing sessions classified as `referral` from AI engines won't be reclassified. Could be a follow-up.
- **AI engine detection via User-Agent**: Some AI crawlers/bots have distinct UAs, but this spec is about human traffic referred by AI engines, not bot traffic.
