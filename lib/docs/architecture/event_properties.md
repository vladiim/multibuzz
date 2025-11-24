# Event Properties Architecture

## Overview

Events in multibuzz use a flexible JSONB `properties` column to store dimensional data. This document defines the standard property keys that are automatically extracted and enriched by the platform.

## Property Key Constants

All property keys are defined in `app/constants/property_keys.rb` to ensure consistency across the codebase.

### URL Components

Automatically extracted from the `url` property sent by the client:

| Key | Constant | Description | Example |
|-----|----------|-------------|---------|
| `url` | `PropertyKeys::URL` | Full URL as sent by client | `https://app.example.com/pricing?plan=pro` |
| `host` | `PropertyKeys::HOST` | Domain/subdomain | `app.example.com` |
| `path` | `PropertyKeys::PATH` | URL path | `/pricing` |
| `query_params` | `PropertyKeys::QUERY_PARAMS` | All query parameters as hash | `{"plan": "pro"}` |

**Benefits:**
- **Landing page analysis**: Query by `path = '/pricing'` without parsing full URL
- **Domain segmentation**: Filter by `host = 'app.example.com'` vs `blog.example.com`
- **Query param dimensions**: Access non-UTM params like `?plan=pro` or `?variant=b`

### Referrer Components

Automatically extracted from the `referrer` property:

| Key | Constant | Description | Example |
|-----|----------|-------------|---------|
| `referrer` | `PropertyKeys::REFERRER` | Full referrer URL | `https://google.com/search?q=analytics` |
| `referrer_host` | `PropertyKeys::REFERRER_HOST` | Referrer domain | `google.com` |
| `referrer_path` | `PropertyKeys::REFERRER_PATH` | Referrer path | `/search` |

**Benefits:**
- **Referrer analysis**: Group by `referrer_host` without parsing
- **Search engine detection**: Match `referrer_host` against known search engines
- **Social platform detection**: Match `referrer_host` against social networks

### UTM Parameters

Automatically extracted from URL query string:

| Key | Constant | Description |
|-----|----------|-------------|
| `utm_source` | `PropertyKeys::UTM_SOURCE` | Campaign source (e.g., `google`, `facebook`) |
| `utm_medium` | `PropertyKeys::UTM_MEDIUM` | Campaign medium (e.g., `cpc`, `email`) |
| `utm_campaign` | `PropertyKeys::UTM_CAMPAIGN` | Campaign name (e.g., `spring_sale`) |
| `utm_content` | `PropertyKeys::UTM_CONTENT` | Ad content variant |
| `utm_term` | `PropertyKeys::UTM_TERM` | Paid search keywords |

**Extraction logic:**
1. Parse URL query string
2. Extract UTM parameters
3. Preserve existing UTM values if already set in properties
4. Store in root properties object for easy querying

### Attribution

| Key | Constant | Description |
|-----|----------|-------------|
| `channel` | `PropertyKeys::CHANNEL` | Derived marketing channel (see `Channels` module) |

Channels are derived from UTM parameters and referrer using `Sessions::ChannelAttributionService`.

### Funnel Tracking

| Key | Constant | Description | Example |
|-----|----------|-------------|---------|
| `funnel` | `PropertyKeys::FUNNEL` | Funnel identifier | `subscription`, `lead` |
| `funnel_step` | `PropertyKeys::FUNNEL_STEP` | Step name | `pricing_view`, `checkout` |
| `funnel_position` | `PropertyKeys::FUNNEL_POSITION` | Numeric position | `1`, `2`, `3` |

These are optional and set by the client for conversion funnel analysis.

### Request Metadata

Server-enriched metadata nested under `request_metadata`:

```json
{
  "request_metadata": {
    "ip_address": "192.168.1.0",
    "user_agent": "Mozilla/5.0...",
    "language": "en-US,en;q=0.9",
    "dnt": "1"
  }
}
```

**Privacy**: IP addresses are anonymized by masking the last octet (IPv4) or last 80 bits (IPv6).

## Example Event Properties

### Minimal Page View

**Client sends:**
```json
{
  "event_type": "page_view",
  "url": "https://example.com/pricing"
}
```

**Server enriches to:**
```json
{
  "url": "https://example.com/pricing",
  "host": "example.com",
  "path": "/pricing",
  "query_params": {},
  "channel": "direct",
  "request_metadata": {
    "ip_address": "192.168.1.0",
    "user_agent": "Mozilla/5.0...",
    "language": "en-US",
    "dnt": "1"
  }
}
```

### Page View with UTM Parameters

**Client sends:**
```json
{
  "event_type": "page_view",
  "url": "https://example.com/pricing?utm_source=google&utm_medium=cpc&plan=pro",
  "referrer": "https://google.com/search?q=analytics"
}
```

**Server enriches to:**
```json
{
  "url": "https://example.com/pricing?utm_source=google&utm_medium=cpc&plan=pro",
  "host": "example.com",
  "path": "/pricing",
  "query_params": {
    "utm_source": "google",
    "utm_medium": "cpc",
    "plan": "pro"
  },
  "utm_source": "google",
  "utm_medium": "cpc",
  "utm_campaign": null,
  "utm_content": null,
  "utm_term": null,
  "referrer": "https://google.com/search?q=analytics",
  "referrer_host": "google.com",
  "referrer_path": "/search",
  "channel": "paid_search",
  "request_metadata": { ... }
}
```

## Database Indexes

The following GIN indexes enable fast querying on JSONB properties:

```sql
-- Individual UTM parameters
CREATE INDEX index_events_on_utm_source ON events USING gin ((properties -> 'utm_source'));
CREATE INDEX index_events_on_utm_medium ON events USING gin ((properties -> 'utm_medium'));
CREATE INDEX index_events_on_utm_campaign ON events USING gin ((properties -> 'utm_campaign'));

-- URL components (to be added)
CREATE INDEX index_events_on_host ON events USING gin ((properties -> 'host'));
CREATE INDEX index_events_on_path ON events USING gin ((properties -> 'path'));

-- Full properties index for flexible queries
CREATE INDEX index_events_on_properties ON events USING gin (properties);
```

## Usage in Code

### Accessing Properties

Use the `Event::PropertyAccess` concern for type-safe access:

```ruby
event = Event.find(123)
event.utm_source    # "google"
event.host          # "example.com"
event.path          # "/pricing"
event.query_params  # {"plan" => "pro"}
```

### Querying by Properties

```ruby
# Find events by landing page
Event.where("properties->>'path' = ?", "/pricing")

# Find events by host
Event.where("properties->>'host' = ?", "app.example.com")

# Find events with specific query param
Event.where("properties->'query_params'->>'plan' = ?", "pro")

# Find events by UTM source
Event.where("properties->>'utm_source' = ?", "google")
```

### Using Constants

Always use constants instead of magic strings:

```ruby
# ✅ GOOD
Event.where("properties->? = ?", PropertyKeys::HOST, "example.com")

# ❌ BAD
Event.where("properties->>'host' = ?", "example.com")
```

## Extension Guidelines

### Adding New Auto-Extracted Properties

1. Add constant to `app/constants/property_keys.rb`
2. Update `AUTO_EXTRACTED` array
3. Add to `INDEXED` array if needs fast querying
4. Update enrichment service
5. Add accessor method to `Event::PropertyAccess`
6. Add GIN index migration if needed
7. Update this documentation

### Adding Client-Defined Properties

Clients can send any custom properties. No code changes needed:

```json
{
  "event_type": "page_view",
  "url": "https://example.com",
  "properties": {
    "page_title": "Pricing",
    "experiment_variant": "b",
    "user_segment": "enterprise"
  }
}
```

These are preserved and queryable via JSONB operators.

## Performance Considerations

- **GIN indexes**: Enable fast `WHERE properties->>'key' = value` queries
- **JSONB storage**: Efficient binary format, faster than JSON text
- **Selective indexing**: Only index high-cardinality dimensions (UTM, host, path)
- **Avoid deep nesting**: Keep properties flat for query performance

## Migration Path

### Existing Events

Events created before host/path extraction will not have these fields. Two options:

1. **Accept sparse data**: Query with `WHERE properties->>'host' IS NOT NULL`
2. **Backfill**: Run background job to parse existing `url` values

### Schema Evolution

The JSONB approach allows adding new property keys without migrations. Simply:
1. Update enrichment service
2. Add constant
3. Deploy

New events get new fields. Old events remain queryable.

## Related Files

- `app/constants/property_keys.rb` - Property key constants
- `app/constants/utm_keys.rb` - UTM parameter constants
- `app/constants/channels.rb` - Channel taxonomy
- `app/services/events/enrichment_service.rb` - Property extraction logic
- `app/models/concerns/event/property_access.rb` - Property accessors
- `db/migrate/*_create_events.rb` - Schema and indexes
