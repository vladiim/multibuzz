# Channel Classification Specification

**Status**: Phase 0-1 Complete, Phase 2-3 Partial
**Last Updated**: 2026-01-10
**Priority**: P0 - Critical (Core Product Functionality)

---

## Executive Summary

Channel attribution is misclassifying traffic. Facebook paid ads are appearing as "paid_search", click identifiers (gclid, gbraid) are being ignored, and UTM pattern variations aren't matched. This spec documents the issues and improvement plan.

---

## 1. Production Data Analysis (2025-12-11)

### 1.1 Channel Distribution

| Channel | Sessions | Notes |
|---------|----------|-------|
| direct | 39 | Includes internal traffic (stage, localhost) |
| paid_search | 34 | **Includes Facebook ads (WRONG)** |
| referral | 23 | |
| other | 19 | **Includes valid traffic with pattern variations** |
| organic_search | 17 | Working correctly |
| email | 12 | Working correctly |
| organic_social | 2 | |
| paid_social | 2 | **Should be higher - FB ads going to paid_search** |

### 1.2 UTM Medium Distribution

| utm_medium | Count | Current Channel | Correct Channel |
|------------|-------|-----------------|-----------------|
| cpc | 26 | paid_search | paid_search ✓ |
| organic | 13 | organic_search | organic_search ✓ |
| email | 12 | email | email ✓ |
| paid_social | 11 | **other** | paid_social ✗ |
| paid | 9 | **paid_search** | depends on source ✗ |
| paid-social | 1 | **other** | paid_social ✗ |
| social | 1 | organic_social | organic_social ✓ |
| rss | 1 | **other** | referral or new channel |

### 1.3 Click IDs in Events (Not Being Used)

| Click ID | Events | Current Usage |
|----------|--------|---------------|
| gclid | 24 | **Not extracted** |
| gbraid | 20 | **Not extracted** |

### 1.4 Specific Misclassification Examples

**Facebook Ads → Paid Search (WRONG)**
```
Session 139: utm_medium=paid, utm_source=fb, referrer=m.facebook.com
  Current: paid_search
  Should be: paid_social

Session 128: utm_medium=paid, utm_source=fb, referrer=m.facebook.com
  Current: paid_search
  Should be: paid_social
```

**Valid UTM Patterns → Other (WRONG)**
```
Session 109: utm_medium=paid-social, utm_source=facebook
  Current: other
  Should be: paid_social (hyphen not matched)

Session 41: utm_medium=paid_social, utm_source=facebook
  Current: other
  Should be: paid_social (underscore not matched)
```

**Google Places Click IDs → Other**
```
Session 100: utm_term=plcid_8067905893793481977, referrer=google.com
  Current: other
  Should be: paid_search or local_ads (Google Places)
```

**Internal Traffic → Direct**
```
Session 144: referrer=stage.petresorts.io
  Current: direct
  Should be: filtered as internal OR referral
```

### 1.5 Referrer Domain Distribution

| Domain | Count | Notes |
|--------|-------|-------|
| www.google.com | 25 | Search (paid + organic) |
| stage.petresorts.io | 15 | **Internal - should exclude** |
| localhost | 12 | **Internal - should exclude** |
| google.com | 4 | Search |
| m.facebook.com | 4 | Social |
| *.pettechpro.com.au | 7 | **Internal - should exclude** |

---

## 2. Root Cause Analysis

### 2.1 Pattern Matching Gaps

**Current pattern for paid_search**:
```ruby
/^(cpc|ppc|paid)$/i => Channels::PAID_SEARCH
```

**Problem**: `utm_medium=paid` matches but doesn't check `utm_source`. Facebook ads with `utm_medium=paid` + `utm_source=fb` get classified as paid_search.

**Missing patterns**:
- `paid-social` (hyphenated)
- `paid_social` (underscored)
- `paidsocial` (no separator)

### 2.2 Click ID Extraction Not Implemented

Events contain URLs with `gclid` and `gbraid` but:
- Not extracted from URL during event processing
- Not stored on session record
- Not used in channel classification

### 2.3 Internal Traffic Not Filtered

Referrers from staging/localhost/internal domains should be:
- Excluded from analytics, OR
- Marked as internal/test traffic

### 2.4 Google Places Click IDs (plcid)

`utm_term=plcid_*` indicates Google Business Profile / Maps traffic. Currently falls to "other".

### 2.5 URL Normalization Missing

No standardization of URLs before extraction, leading to inconsistencies:
- `http://` vs `https://` treated differently
- `www.google.com` vs `google.com` may not match patterns
- Case sensitivity issues in domain matching
- Trailing slashes affecting parsing

---

## 3. Industry Standard (GA4)

### 3.1 GA4 Classification Hierarchy

1. **Google Ads integration** (gclid decodes ad network type)
2. **DV360 integration** (dclid)
3. **Click identifier detection** (msclkid, fbclid, etc.)
4. **UTM parameters**
5. **Source category lookup** (800+ known sources)
6. **Referrer pattern matching**
7. **Unassigned fallback**

### 3.2 GA4 Channels (18 total)

| Channel | Key Signals |
|---------|-------------|
| Direct | No referrer, no UTM |
| Organic Search | Source category = SEARCH, no paid signals |
| Paid Search | Source category = SEARCH + (gclid OR msclkid OR medium=cpc) |
| Organic Social | Source category = SOCIAL, no paid signals |
| Paid Social | Source category = SOCIAL + (fbclid OR medium=paid) |
| Organic Video | Source category = VIDEO, no paid signals |
| Paid Video | Source category = VIDEO + paid signals |
| Display | dclid OR medium=display/banner |
| Organic Shopping | Source category = SHOPPING, no paid signals |
| Paid Shopping | Source category = SHOPPING + paid signals |
| Email | Source category = EMAIL OR medium=email |
| Affiliates | medium=affiliate |
| Referral | Has referrer, doesn't match other channels |
| Audio | medium=audio |
| SMS | medium/source=sms |
| Mobile Push | medium=push/notification |
| Cross-network | Campaign type = Performance Max |
| Unassigned | No rules match |

### 3.3 Source Categories

GA4 maintains 800+ known sources:
- **SOURCE_CATEGORY_SEARCH**: google.com, bing.com, yahoo.com, duckduckgo.com, baidu.com, yandex.ru, ecosia.org
- **SOURCE_CATEGORY_SOCIAL**: facebook.com, instagram.com, twitter.com, linkedin.com, tiktok.com, pinterest.com, reddit.com, snapchat.com
- **SOURCE_CATEGORY_VIDEO**: youtube.com, vimeo.com, dailymotion.com, twitch.tv
- **SOURCE_CATEGORY_SHOPPING**: amazon.com, ebay.com, etsy.com
- **SOURCE_CATEGORY_EMAIL**: mail.google.com, outlook.live.com

---

## 4. Click Identifiers Reference

### 4.1 All Known Click IDs

| Parameter | Platform | Default Channel |
|-----------|----------|-----------------|
| `gclid` | Google Ads | paid_search (can be display/video/shopping) |
| `gclsrc` | Google Ads | paid_search |
| `wbraid` | Google Ads (iOS web) | paid_search |
| `gbraid` | Google Ads (iOS app) | paid_search |
| `dclid` | DoubleClick/DV360 | display |
| `msclkid` | Microsoft Ads | paid_search |
| `fbclid` | Meta/Facebook | paid_social |
| `ttclid` | TikTok | paid_social |
| `li_fat_id` | LinkedIn | paid_social |
| `twclid` | Twitter/X | paid_social |
| `rdt_cid` | Reddit | paid_social |
| `epik` | Pinterest | paid_social |
| `ScCid` | Snapchat | paid_social |
| `sznclid` | Seznam (Czech) | paid_search |

### 4.2 Google Places Click ID

| Parameter | Format | Channel |
|-----------|--------|---------|
| `plcid` (in utm_term) | `plcid_NNNN` | local_ads or paid_search |

### 4.3 Source Aliases (Normalize Before Matching)

| Alias | Canonical |
|-------|-----------|
| fb | facebook |
| ig | instagram |
| tw | twitter |
| x | twitter |
| li | linkedin |
| yt | youtube |
| goog | google |
| msn | microsoft |
| bing | microsoft |

### 4.4 Medium Aliases (Normalize Before Matching)

| Variations | Canonical |
|------------|-----------|
| cpc, ppc, paid-search, paid_search, paidsearch, sem, adwords | paid_search |
| paid-social, paid_social, paidsocial, cpm-social | paid_social |
| social, social-media, social_media, sm | social |
| e-mail, e_mail, email, newsletter | email |
| display, banner, gdn, programmatic | display |
| video, cpv, youtube | video |
| affiliate, affiliates, partner | affiliate |

---

## 5. Proposed Solution

### 5.1 New Classification Hierarchy

```
1. URL Normalization (NEW - preprocessing)
2. Click Identifier Detection (NEW - highest priority)
3. UTM Parameter Classification (existing, enhanced)
4. Source Category Lookup (NEW)
5. Referrer Pattern Matching (existing, enhanced)
6. Direct (fallback)
```

### 5.2 URL & UTM Normalization

**URL standardization**:
- Lowercase domain names
- Strip `www.` prefix for matching
- Normalize protocol (store original, match without)
- Handle trailing slashes consistently
- Decode URL-encoded characters

**UTM value normalization** (layered approach):

1. **Exact alias lookup** (first, fast):
   - `fb` → `facebook`, `cpc` → `paid_search`, etc.
   - Covers 95% of cases

2. **Separator normalization**:
   - Convert `-` and spaces to `_`
   - `paid-social` → `paid_social`

3. **Compound word detection**:
   - Split and match: `paidsocial` → detect `paid` + `social`
   - Only for known compound patterns

4. **Levenshtein distance** (sources only, threshold ≤2):
   - Catch typos: `facebok` → `facebook`
   - **NOT for mediums** (too risky: `cpc` vs `cpv`)

5. **Store original, normalize for matching**

**Why NOT Word2Vec/Embeddings**:
- UTM values are short codes, not natural language
- Unpredictable semantic matches (`social_media` might match `paid_social`)
- Overkill for a structured classification problem

**Why NOT Soundex/Phonetic**:
- UTM values often aren't words (`cpc`, `ppc`, `gdn`)
- English-centric

### 5.3 Key Logic Changes

**Fix paid/social detection**:
- If `utm_medium` matches paid pattern AND `utm_source` matches social pattern → `paid_social`
- If `utm_medium` matches paid pattern AND `utm_source` matches search pattern → `paid_search`
- If `utm_medium` matches paid pattern (alone) → check referrer domain for classification

**Expand UTM patterns**:
- `paid[-_]?social|paidsocial` → paid_social
- `paid[-_]?search|paidsearch|sem` → paid_search
- `cpc|ppc` (with source check) → paid_search or paid_social

**Add click ID extraction**:
- Extract from event URL during processing
- Store on session: `click_id_type`, `click_id_value`, `ad_platform`
- Use in classification (highest priority)

**Filter internal traffic**:
- Configure internal domains list per account
- Exclude from channel attribution OR mark as `internal`

### 5.4 Database Changes

**sessions table** (add columns):
- `click_id_type` (string) - gclid, msclkid, fbclid, etc.
- `click_id_value` (string) - The actual ID
- `ad_platform` (string) - google, microsoft, meta, etc.

**source_categories table** (new):
- `domain` (string, indexed)
- `category` (string) - search, social, video, shopping, email
- `source_name` (string) - Google, Facebook, YouTube, etc.
- `keyword_param` (string) - Query param for search term
- `data_origin` (string) - snowplow, matomo, custom

**accounts table** (add column):
- `internal_domains` (string array) - Domains to exclude from attribution

### 5.5 New/Enhanced Channels

**Split existing**:
- `video` → `paid_video` / `organic_video`

**Add new**:
- `paid_shopping` / `organic_shopping`
- `audio`
- `sms`
- `push`
- `cross_network`
- `local_ads` (Google Places/Maps)

---

## 6. LLM-Assisted Classification

### 6.1 Recommendation: NOT for Real-Time

**Against using LLM for real-time classification**:
- **Latency**: 200-500ms per API call unacceptable for session creation
- **Cost**: At scale, classifying every session is expensive
- **Determinism**: Same inputs must give same outputs; LLMs can vary
- **Simplicity**: Rule-based systems sufficient when rules are comprehensive

### 6.2 Where LLM IS Useful

**Batch reclassification of "other" traffic**:
- Scheduled job to review sessions in "other" channel
- LLM suggests correct channel based on all available signals
- Human review before applying changes
- Helps identify new patterns to add to rules

**Suggesting new patterns**:
- Weekly report of unclassified traffic
- LLM analyzes and suggests new UTM patterns or source categories
- Patterns added to codebase after review

**One-time domain categorization**:
- When new referrer domain appears frequently
- LLM researches domain and suggests category
- Added to source_categories table

### 6.3 Implementation Approach (If Used)

- Solid Queue background job, not real-time
- Haiku model for cost efficiency
- Structured output (channel enum)
- Confidence threshold (>90%) for auto-apply, else human review
- Rate-limited to avoid cost spikes

---

## 7. External Data Sources

### 7.1 Snowplow referer-parser

**URL**: https://github.com/snowplow-referer-parser/referer-parser

- `referers.yml` with search engines, social networks
- Updated daily, Apache 2.0 license
- Includes keyword extraction params

### 7.2 Matomo Search/Social Lists

**URL**: https://github.com/matomo-org/searchengine-and-social-list

- More comprehensive than Snowplow
- GPL licensed

---

## 8. Implementation Checklist

### Phase 0: Immediate Fixes (P0) ✅ COMPLETE

- [x] Create `Sessions::UtmNormalizationService` for UTM value normalization ✅
  - [x] Exact alias lookup (from constants) ✅ `app/constants/utm_aliases.rb`
  - [x] Separator normalization (`-` and space → `_`) ✅ `MediumNormalizer.parameterize`
  - [x] Compound word detection (`paidsocial` → `paid_social`) ✅ via alias lookup
  - [ ] Levenshtein matching for sources only (threshold ≤2) - SKIPPED (risk vs benefit)
  - [ ] Log unmatched values for pattern discovery - NOT DONE
- [x] Create `Sessions::UrlNormalizationService` for URL/domain normalization ✅
  - [x] Lowercase domains ✅
  - [x] Strip `www.` prefix ✅
  - [x] Decode URL-encoded characters ✅
- [x] Fix `utm_medium=paid` to check `utm_source` before classifying ✅
  - Lambda `paid_channel` checks `social_source?` in `ChannelAttributionService`
- [x] Add `plcid` detection in `utm_term` for Google Places ✅
  - `ClickIdentifiers.plcid?` method with `PLCID_PATTERN`
- [ ] Configure internal domains filter (stage, localhost, pettechpro) - PARTIAL
  - Basic `internal_referrer?` check exists (compares page_host)
  - Per-account `internal_domains` NOT YET IMPLEMENTED
- [x] Tests for Facebook ads with `utm_medium=paid` → paid_social ✅
  - `channel_attribution_service_test.rb:150`
- [x] Tests for all medium alias variations ✅
  - `utm_normalization_service_test.rb`

### Phase 1: Click Identifier Detection (P0) ✅ COMPLETE

- [x] Create `app/constants/click_identifiers.rb` ✅
  - 17 click IDs: gclid, gbraid, wbraid, dclid, gclsrc, msclkid, fbclid, ttclid, li_fat_id, twclid, epik, sclid, ScCid, rdt_cid, qclid, vmcid, yclid, sznclid
- [x] Create `Sessions::ClickIdCaptureService` ✅
  - Extracts click IDs from URL params
  - `infer_source()` and `infer_channel()` methods
- [ ] Add migration for click_id columns on sessions - NOT DONE
  - Click IDs extracted but not persisted to session columns
- [x] Update `ChannelAttributionService` to check click IDs ✅
  - 2026-01-10: Now checks click IDs FIRST (GA4 alignment)
- [x] Update event/session processing to extract click IDs ✅
- [x] Tests for gclid, msclkid, fbclid, gbraid, etc. ✅
  - `click_id_capture_service_test.rb`
  - `channel_attribution_service_test.rb:165-180`

### Phase 2: Enhanced UTM Patterns (P1) ✅ MOSTLY COMPLETE

- [x] Expand all pattern variations (hyphens, underscores, no separator) ✅
  - `utm_aliases.rb` covers all variations
- [ ] Add paid/organic detection for video channel - NOT DONE
  - Currently single `video` channel (GA4 has `paid_video`/`organic_video`)
- [ ] Add new channel patterns (audio, sms, push, shopping) - NOT DONE
  - 11 channels vs GA4's 18
- [x] Tests for all pattern variations ✅

### Phase 3: Source Category Database (P1) ✅ COMPLETE

- [x] Create `source_categories` table and model ✅
  - Named `referrer_sources` table with `ReferrerSource` model
- [x] Import Snowplow referers.yml ✅
  - Plus Matomo search engines, social networks, spam list
- [x] Create `SourceCategories::LookupService` ✅
  - `ReferrerSources::LookupService` with caching
- [x] Update classification to use source categories ✅
  - `channel_from_lookup` in `ChannelAttributionService`
- [x] Schedule daily sync job ✅
  - `ReferrerSources::SyncService`

### Phase 4: Internal Traffic Filtering (P1) - PARTIAL

- [ ] Add `internal_domains` column to accounts - NOT DONE
- [ ] UI in account settings to configure internal domains - NOT DONE
- [x] Filter internal traffic from attribution ✅
  - Basic `internal_referrer?` compares referrer to page_host
- [ ] Option to mark as `internal` channel vs exclude entirely - NOT DONE

### Phase 5: LLM-Assisted Review (P2) - NOT STARTED

- [ ] Background job to review "other" channel sessions
- [ ] LLM prompt for channel suggestion
- [ ] Admin UI for reviewing suggestions
- [ ] Weekly pattern suggestion report

### Phase 6: Backfill & Verification (P1) - NOT STARTED

- [ ] Backfill script to re-extract click IDs from event URLs
- [ ] Re-classify existing sessions
- [ ] Channel distribution comparison report
- [ ] Anomaly detection alert

---

## 9. Testing Strategy

### Unit Tests
- URL normalization (case, www, protocol, trailing slash)
- Click ID detection for all 14+ identifiers
- UTM pattern matching for all variations
- Source + medium combination logic
- Internal domain filtering

### Integration Tests
- Google Ads (gclid) → paid_search
- Facebook Ads (utm_medium=paid, source=fb) → paid_social
- Facebook Ads (fbclid) → paid_social
- Organic Google (referrer only) → organic_search
- Internal referrer → excluded or internal

---

## 10. Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Paid Social accuracy | ~6% | >95% |
| Other/Unassigned % | 13% | <5% |
| Click ID coverage | 0% | >90% |
| Internal traffic in analytics | Present | Excluded |

---

## 11. References

- [GA4 Default Channel Group](https://support.google.com/analytics/answer/9756891)
- [Snowplow Referer Parser](https://github.com/snowplow-referer-parser/referer-parser)
- [Matomo Channel Attribution](https://matomo.org/guide/reports/acquisition-and-marketing-channels/)
- [Click Identifiers List](https://www.appfromlab.com/posts/list-of-click-identifiers/)
- [Google Click Identifier](https://support.google.com/google-ads/answer/9744275)
