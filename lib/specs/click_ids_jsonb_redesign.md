# Click IDs JSONB Redesign

## Status: Approved
## Author: Claude
## Date: 2025-12-11

---

## 1. Problem Statement

The current implementation adds individual database columns for each click identifier:

```ruby
# db/migrate/20251211035212_add_click_ids_to_sessions.rb
add_column :sessions, :gclid, :string
add_column :sessions, :gbraid, :string
add_column :sessions, :wbraid, :string
add_column :sessions, :dclid, :string
add_column :sessions, :msclkid, :string
add_column :sessions, :fbclid, :string
add_column :sessions, :ttclid, :string
add_column :sessions, :li_fat_id, :string
add_column :sessions, :twclid, :string
add_column :sessions, :epik, :string
add_column :sessions, :sclid, :string

# db/migrate/20251211064836_add_additional_click_ids_to_sessions.rb
add_column :sessions, :gclsrc, :string
add_column :sessions, :scclid, :string
add_column :sessions, :rdt_cid, :string
add_column :sessions, :qclid, :string
add_column :sessions, :vmcid, :string
add_column :sessions, :yclid, :string
add_column :sessions, :sznclid, :string
```

### Problems with this approach:

1. **Schema changes for each new ID** - Every new ad platform requires a migration
2. **Column bloat** - 18+ columns where most sessions have 0-2 values (rest are NULL)
3. **Maintenance burden** - Adding Taboola, Outbrain, or future platforms means new migrations
4. **Inflexible** - Cannot handle unknown/custom click IDs from new platforms
5. **Query complexity** - Checking "has any click ID" requires OR across all columns

---

## 2. Solution: JSONB Column

Store all click identifiers in a single JSONB column on sessions.

### 2.1 Schema Change

```ruby
# New migration
class AddClickIdsJsonbToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :click_ids, :jsonb, default: {}, null: false
    add_index :sessions, :click_ids, using: :gin
  end
end
```

### 2.2 Data Structure

```ruby
# Example session.click_ids values:

# Google Ads click
{ "gclid" => "CjwKCAiA..." }

# Facebook ad with Google Analytics
{ "fbclid" => "IwAR3x...", "gclid" => "abc123" }

# Multiple identifiers (rare but possible)
{ "gclid" => "abc", "gbraid" => "xyz", "gclsrc" => "aw.ds" }

# No click IDs (direct/organic traffic)
{}
```

### 2.3 Query Patterns

```ruby
# Has any click ID (paid traffic signal)
Session.where("click_ids != '{}'")

# Has specific click ID type
Session.where("click_ids ? 'gclid'")

# Match specific click ID value
Session.where("click_ids->>'gclid' = ?", "abc123")

# Has any Google click ID
Session.where("click_ids ?| array['gclid', 'gbraid', 'wbraid', 'dclid', 'gclsrc']")

# Count sessions by click ID type (analytics)
Session.select("jsonb_object_keys(click_ids) as click_type, count(*)")
       .where("click_ids != '{}'")
       .group("click_type")
```

---

## 3. Implementation Plan

### 3.1 Migrations to Remove

Delete these migration files (not yet applied to production):

- `db/migrate/20251211035212_add_click_ids_to_sessions.rb`
- `db/migrate/20251211064836_add_additional_click_ids_to_sessions.rb`

### 3.2 New Migration

Create single migration:

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_click_ids_to_sessions.rb
class AddClickIdsToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :click_ids, :jsonb, default: {}, null: false
    add_index :sessions, :click_ids, using: :gin
  end
end
```

### 3.3 Service Updates

Update `Sessions::ClickIdCaptureService` to return a hash (already does this).

Update `Sessions::CreationService` to store hash directly:

```ruby
# Before (individual columns)
session.gclid = click_ids[:gclid]
session.fbclid = click_ids[:fbclid]
# ... 18 more lines

# After (single JSONB)
session.click_ids = click_ids
```

### 3.4 Model Updates

No changes needed - JSONB columns work automatically in Rails.

Optional convenience methods:

```ruby
# app/models/concerns/session/click_id_helpers.rb
module Session::ClickIdHelpers
  extend ActiveSupport::Concern

  def has_click_id?
    click_ids.present? && click_ids.any?
  end

  def click_id_types
    click_ids.keys
  end

  def primary_click_id
    # Returns first click ID based on priority order
    ClickIdentifiers::ALL.find { |id| click_ids[id].present? }
  end
end
```

---

## 4. Benefits

| Aspect | Individual Columns | JSONB |
|--------|-------------------|-------|
| New click ID | Migration required | Constants only |
| Columns per session | 18+ (mostly NULL) | 1 |
| Unknown click IDs | Cannot store | Stored automatically |
| Query "has any" | OR across all columns | `click_ids != '{}'` |
| Index size | 18 separate indexes | 1 GIN index |
| Schema stability | Changes frequently | Stable |

---

## 5. Alternatives Considered

### 5.1 Separate Table (Rejected)

```ruby
create_table :click_identifiers do |t|
  t.references :session, null: false
  t.string :identifier_type, null: false
  t.string :identifier_value, null: false
end
```

**Why rejected:**
- Extra JOIN for every session query
- More complex than needed for write-once data
- Click IDs don't need their own lifecycle/metadata
- JSONB is simpler and sufficient

### 5.2 Array Column (Rejected)

```ruby
add_column :sessions, :click_ids, :string, array: true, default: []
```

**Why rejected:**
- Loses the type information (which click ID is which)
- Would need separate column for types or encoded format
- JSONB is more flexible and queryable

---

## 6. Files to Modify

### Delete:
- `db/migrate/20251211035212_add_click_ids_to_sessions.rb`
- `db/migrate/20251211064836_add_additional_click_ids_to_sessions.rb`

### Create:
- `db/migrate/YYYYMMDDHHMMSS_add_click_ids_to_sessions.rb` (JSONB version)

### Update:
- `app/services/sessions/creation_service.rb` - Store click_ids hash directly
- `app/constants/click_identifiers.rb` - Already correct, no changes needed
- `app/services/sessions/click_id_capture_service.rb` - Already returns hash, no changes needed

### Tests:
- `test/services/sessions/click_id_capture_service_test.rb` - Already correct
- `test/services/sessions/creation_service_test.rb` - Update to check click_ids JSONB

---

## 7. Rollback Plan

If issues arise:
1. JSONB column can be dropped with simple migration
2. No data loss risk (click IDs are derived from event URLs, can be re-extracted)
3. Can revert to individual columns if absolutely necessary (not recommended)

---

## 8. Future Considerations

### 8.1 Google Places Click ID (plcid)

The `plcid` appears in `utm_term` (e.g., `utm_term=plcid_8067905893793481977`), not as a URL parameter. This is handled separately in `ClickIdentifiers.plcid?()` and doesn't need storage in `click_ids` column.

### 8.2 Adding New Click IDs

To add support for a new click ID (e.g., Taboola):

1. Add constant to `app/constants/click_identifiers.rb`:
   ```ruby
   TBLCI = "tblci"  # Taboola Click ID
   ```

2. Add to `ALL`, `SOURCE_MAP`, and `CHANNEL_MAP` arrays

3. No migration needed - JSONB stores it automatically

### 8.3 Analytics Queries

For dashboard analytics on click ID distribution:

```sql
SELECT
  key as click_id_type,
  count(*) as session_count
FROM sessions, jsonb_each_text(click_ids)
WHERE click_ids != '{}'
GROUP BY key
ORDER BY session_count DESC;
```
