# Referrer Source Classification System

## Overview

A database-backed referrer classification system that syncs nightly from multiple upstream data sources to accurately classify web traffic by channel (search, social, email, etc.).

---

## Features

### 1. Referrer Classification
- Classify any referrer URL into a channel (search, social, email, video, etc.)
- Return source name (Google, Facebook, LinkedIn, etc.)
- Extract search keywords when available
- Identify spam referrers

### 2. Multi-Source Data Sync
- Pull from multiple authoritative upstream sources
- Merge and deduplicate across sources
- Prioritize sources when conflicts exist
- Track data provenance (which source provided each record)

### 3. Nightly Sync Job
- Scheduled background job runs nightly
- Fetches latest data from all upstream sources
- Upserts records (insert new, update existing)
- Logs sync statistics and errors

### 4. Caching Layer
- In-memory cache for high-performance lookups
- Cache invalidation after sync completes
- Fallback to database on cache miss

---

## Data Sources

### Primary Sources

| Source | URL | Provides | Update Frequency |
|--------|-----|----------|------------------|
| Matomo SearchEngines | `github.com/matomo-org/searchengine-and-social-list/SearchEngines.yml` | 500+ search engines with keyword params | Weekly |
| Matomo Socials | `github.com/matomo-org/searchengine-and-social-list/Socials.yml` | 120+ social networks | Weekly |
| Matomo Spam List | `github.com/matomo-org/referrer-spam-list/spammers.txt` | 1000+ spam domains | Daily |
| Snowplow Referers | `s3-eu-west-1.amazonaws.com/.../referers-latest.json` | Search, social, email providers | Daily |

### Source Priority (for conflicts)
1. Custom (internal overrides)
2. Matomo (most comprehensive)
3. Snowplow (battle-tested)

---

## Data Model

### ReferrerSource

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key |
| `domain` | string | Domain pattern (e.g., "google.com", "facebook.com") |
| `source_name` | string | Human-readable name (e.g., "Google", "Facebook") |
| `medium` | enum | Channel type: search, social, email, video, shopping, news |
| `keyword_param` | string | URL param containing search term (e.g., "q" for Google) |
| `is_spam` | boolean | Whether this is a known spam referrer |
| `data_origin` | enum | Which upstream source provided this record |
| `created_at` | datetime | Record creation timestamp |
| `updated_at` | datetime | Last update timestamp |

### Indexes
- `domain` (unique) - Primary lookup key
- `medium` - Filter by channel type
- `is_spam` - Quick spam filtering
- `data_origin` - Track data provenance

### Constants (No Magic Strings)

Following project conventions, all enum values defined as constants in dedicated modules.

**File: `app/constants/referrer_sources/mediums.rb`**

| Constant | Value | Description |
|----------|-------|-------------|
| `SEARCH` | `"search"` | Search engines (Google, Bing, DuckDuckGo) |
| `SOCIAL` | `"social"` | Social networks (Facebook, Twitter, LinkedIn) |
| `EMAIL` | `"email"` | Webmail providers (Gmail, Outlook, Yahoo Mail) |
| `VIDEO` | `"video"` | Video platforms (YouTube, Vimeo, TikTok) |
| `SHOPPING` | `"shopping"` | Shopping/e-commerce (Amazon, eBay) |
| `NEWS` | `"news"` | News aggregators (Google News, Apple News) |
| `ALL` | Array | All valid medium values (frozen) |

**File: `app/constants/referrer_sources/data_origins.rb`**

| Constant | Value | Description |
|----------|-------|-------------|
| `MATOMO_SEARCH` | `"matomo_search"` | From Matomo SearchEngines.yml |
| `MATOMO_SOCIAL` | `"matomo_social"` | From Matomo Socials.yml |
| `MATOMO_SPAM` | `"matomo_spam"` | From Matomo spammers.txt |
| `SNOWPLOW` | `"snowplow"` | From Snowplow referers.json |
| `CUSTOM` | `"custom"` | Internal/manual additions |
| `ALL` | Array | All valid data origin values (frozen) |

### Source Priority Constants

**File: `app/constants/referrer_sources/data_origins.rb`**

| Constant | Value | Description |
|----------|-------|-------------|
| `PRIORITY` | Hash | Priority order for conflict resolution (higher = preferred) |

Priority order: `CUSTOM` (5) > `MATOMO_*` (3) > `SNOWPLOW` (1)

---

## Design Patterns

### Service Objects
Following project conventions, all business logic in service objects with only `initialize` and `call` as public methods.

| Service | Responsibility |
|---------|----------------|
| `ReferrerSources::LookupService` | Find matching source for a referrer URL |
| `ReferrerSources::SyncService` | Orchestrate sync from all upstream sources |
| `ReferrerSources::Parsers::MatomoSearchParser` | Parse Matomo SearchEngines.yml |
| `ReferrerSources::Parsers::MatomoSocialParser` | Parse Matomo Socials.yml |
| `ReferrerSources::Parsers::MatomoSpamParser` | Parse Matomo spammers.txt |
| `ReferrerSources::Parsers::SnowplowParser` | Parse Snowplow referers.json |

### Background Jobs
Thin wrapper around sync service.

| Job | Schedule | Responsibility |
|-----|----------|----------------|
| `ReferrerSources::SyncJob` | Nightly (2 AM) | Invoke SyncService |

### Caching Strategy
- Use `Rails.cache` with Solid Cache (database-backed, per project stack)
- Cache key: `referrer_sources/domain/{normalized_domain}`
- TTL: Until next sync (invalidate all on sync completion)
- Cache entire lookup result including source_name, medium, keyword_param

---

## Naming Conventions

### Module Namespace
All referrer source code under `ReferrerSources::` namespace.

### File Structure
```
app/
  constants/
    referrer_sources/
      mediums.rb
      data_origins.rb
  models/
    referrer_source.rb
    concerns/
      referrer_source/
        validations.rb
        scopes.rb
  services/
    referrer_sources/
      lookup_service.rb
      sync_service.rb
      parsers/
        base_parser.rb
        matomo_search_parser.rb
        matomo_social_parser.rb
        matomo_spam_parser.rb
        snowplow_parser.rb
  jobs/
    referrer_sources/
      sync_job.rb
test/
  models/
    referrer_source_test.rb
  services/
    referrer_sources/
      lookup_service_test.rb
      sync_service_test.rb
      parsers/
        matomo_search_parser_test.rb
        matomo_social_parser_test.rb
        matomo_spam_parser_test.rb
        snowplow_parser_test.rb
  fixtures/
    referrer_sources.yml
```

### Method Naming
- `LookupService#call` returns `{ source_name:, medium:, keyword_param:, is_spam: }` or `nil`
- `SyncService#call` returns `{ success:, stats: { created:, updated:, deleted: } }`
- Parser `#call` returns array of hashes ready for upsert

---

## Integration with Channel Attribution

### Updated Flow
1. Check UTM parameters first (existing logic)
2. If no UTM match, query `ReferrerSources::LookupService` with referrer URL
3. Map lookup result to channel constant
4. Fall back to existing regex patterns if no database match

### Medium to Channel Mapping
| ReferrerSource.medium | Channels Constant |
|-----------------------|-------------------|
| `search` | `Channels::ORGANIC_SEARCH` |
| `social` | `Channels::ORGANIC_SOCIAL` |
| `email` | `Channels::EMAIL` |
| `video` | `Channels::VIDEO` |
| `shopping` | `Channels::REFERRAL` |
| `news` | `Channels::REFERRAL` |

---

## Sync Process

### Nightly Sync Steps
1. Fetch data from all upstream sources (parallel HTTP requests)
2. Parse each source into normalized format
3. Merge records, applying source priority for conflicts
4. Upsert all records in single transaction
5. Invalidate cache
6. Log sync statistics

### Error Handling
- Individual source failures don't block other sources
- Retry failed sources up to 3 times with exponential backoff
- Alert on complete sync failure (all sources failed)
- Keep existing data on sync failure (don't delete)

### Sync Statistics
Track and log:
- Records created
- Records updated
- Records unchanged
- Source fetch times
- Total sync duration

---

## Implementation Order

1. **Model** - ReferrerSource with validations and scopes
2. **Parsers** - One parser per upstream source
3. **SyncService** - Orchestrate parsing and upserting
4. **SyncJob** - Background job wrapper
5. **LookupService** - Query and cache referrer lookups
6. **Integration** - Update ChannelAttributionService to use LookupService

---

## Code Review Findings

### Brittleness Issues (Must Fix)

| Issue | Severity | Location | Fix |
|-------|----------|----------|-----|
| N+1 on sync | HIGH | `SyncService#upsert_records` | Use `upsert_all` with conflict resolution |
| No transaction | HIGH | `SyncService#upsert_records` | Wrap in `ActiveRecord::Base.transaction` |
| No HTTP timeout | MEDIUM | `SyncService#fetch_source` | Add `Net::HTTP` read/open timeout |
| No retry logic | MEDIUM | `SyncService#fetch_source` | Add exponential backoff (3 retries) |
| Naive root_domain | MEDIUM | `LookupService#root_domain` | Use `public_suffix` gem for proper TLD handling |
| Cache key collision | MEDIUM | `LookupService#cache_key` | Sanitize domain before cache key |
| Nuclear cache invalidation | LOW | `SyncService#invalidate_cache` | Only invalidate changed records |

### Code Smells (Should Fix)

| Smell | Location | Fix |
|-------|----------|-----|
| Mixed concerns | `SyncService` | Extract `FetchService` for HTTP logic |
| Silent failures | Parsers | Add logging on parse errors |
| Inconsistent patterns | `LookupService` | Inherit from `ApplicationService` |
| Duplicate domain extraction | Both services | Extract shared `DomainExtractor` |
| No observability | All services | Add Rails logger calls + timing metrics |

### Design Improvements (Nice to Have)

| Improvement | Description |
|-------------|-------------|
| Typed result objects | Replace hash returns with proper result structs |
| Configurable URLs | Move source URLs to Rails config/credentials |
| Bulk operations | Use `insert_all`/`upsert_all` for performance |
| Parallel fetching | Fetch from all sources concurrently |

---

## Implementation Fixes (Priority Order)

### Phase 1: Critical Fixes
1. Wrap sync in transaction
2. Use `upsert_all` instead of N+1
3. Add HTTP timeout (30s)
4. Add logging throughout

### Phase 2: Robustness
5. Add retry logic with exponential backoff
6. Use `public_suffix` gem for proper domain parsing
7. Make `LookupService` inherit from `ApplicationService`
8. Sanitize cache keys

### Phase 3: Observability
9. Add sync duration metrics
10. Add per-source timing
11. Log parse errors with source context

---

## Future Enhancements

- AI assistant detection (ChatGPT, Claude, Perplexity referrers)
- Regional domain expansion (google.co.uk, google.de, etc.)
- Custom per-account overrides
- Admin UI for manual additions
- Sync status dashboard
