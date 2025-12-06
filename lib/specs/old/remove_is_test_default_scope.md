# Remove is_test Default Scope

## Problem

Using `default_scope { where(is_test: false) }` on models causes silent failures in services that forget to unscope for test mode.

**Example failure:** `Conversions::TrackingService` returns 422 "Visitor not found" because `account.visitors.find_by(visitor_id: ...)` silently filters out test visitors.

**Current state:**
- 6 models have `default_scope { production }`
- 11+ places manually unscope with `unscope(where: :is_test)`
- Easy to miss, causing bugs

## Solution

Remove all default scopes. Use explicit `.production` scope in dashboard/UI only.

## Checklist

### 1. Remove default_scope from models

- [ ] `app/models/concerns/visitor/scopes.rb`
- [ ] `app/models/concerns/session/scopes.rb`
- [ ] `app/models/concerns/event/scopes.rb`
- [ ] `app/models/concerns/conversion/scopes.rb`
- [ ] `app/models/concerns/attribution_credit/scopes.rb`
- [ ] `app/models/concerns/identity/scopes.rb`

### 2. Update dashboard queries to use .production

- [ ] `app/services/dashboard/conversions_data_service.rb`
- [ ] `app/services/dashboard/funnel_data_service.rb`
- [ ] `app/controllers/dashboard_controller.rb`
- [ ] `app/controllers/dashboard/*.rb` (check all)

### 3. Remove unscope workarounds from services

- [ ] `app/services/identities/identification_service.rb` (lines 74, 88, 92, 104, 112)
- [ ] `app/services/sessions/creation_service.rb` (lines 73, 100)
- [ ] `app/services/sessions/tracking_service.rb` (line 39)
- [ ] `app/services/visitors/lookup_service.rb` (line 32)
- [ ] `app/models/concerns/visitor/relationships.rb` (line 14)
- [ ] `app/models/concerns/identity/scopes.rb` (line 6 - update test_data scope)

### 4. Update test_data scope definitions

The `test_data` scope currently uses `unscope(where: :is_test).where(is_test: true)` because of the default scope. Simplify to just `where(is_test: true)`.

- [ ] `app/models/concerns/visitor/scopes.rb`
- [ ] `app/models/concerns/session/scopes.rb`
- [ ] `app/models/concerns/event/scopes.rb`
- [ ] `app/models/concerns/conversion/scopes.rb`
- [ ] `app/models/concerns/attribution_credit/scopes.rb`
- [ ] `app/models/concerns/identity/scopes.rb`

### 5. Run tests

- [ ] `bin/rails test` - all tests pass

## Verification

After changes, this should work in production console:

```ruby
# Test visitor should be found without unscope
account.visitors.find_by(visitor_id: "test_visitor_id")

# Dashboard should still only show production data
account.visitors.production.count
```
