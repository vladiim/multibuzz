# Critical Bug Fixes: Gem & Backend Inconsistencies

**Status**: Blocking UAT
**Priority**: P0
**Created**: 2025-11-25

---

## Overview

During documentation review, we discovered 5 critical inconsistencies between the mbuzz-ruby gem, backend API, and documentation that prevent the system from working end-to-end.

---

## Critical Issues

### 1. Timestamp Format Mismatch 🐛

**Impact**: CRITICAL - All gem events will be rejected by backend validation

**Current State**:
- Gem sends: `timestamp: Time.now.to_i` (Unix epoch integer, e.g., `1732550400`)
- Backend expects: ISO8601 string (e.g., `"2025-11-25T10:30:00Z"`)
- Backend validation: `Time.iso8601(event_data["timestamp"])` will raise exception

**Location**:
- Gem: `mbuzz-ruby/lib/mbuzz/client.rb:15, 26`
- Backend: `app/services/events/validation_service.rb:29`
- Backend: `app/services/events/processing_service.rb:81`

**Fix**:
```ruby
# mbuzz-ruby/lib/mbuzz/client.rb
# Change from:
timestamp: Time.now.to_i

# Change to:
timestamp: Time.now.utc.iso8601
```

**Testing**:
```ruby
# Verify gem sends correct format
event = Mbuzz.track(user_id: 1, event: 'Test')
# Should send: { "timestamp": "2025-11-25T10:30:00Z" }

# Verify backend accepts it
response = ValidationService.new.call([event_data])
assert response[:valid]
```

---

### 2. Event Parameter Name Mismatch 🐛

**Impact**: CRITICAL - Events won't be processed correctly

**Current State**:
- Gem sends: `event: "Signup"`
- Backend expects: `event_type: "Signup"`
- Backend code: `event_data["event_type"]` everywhere

**Location**:
- Gem: `mbuzz-ruby/lib/mbuzz/client.rb:10-16`
- Backend: `app/services/events/validation_service.rb:3`
- Backend: `app/services/events/processing_service.rb:78`

**Fix**:
```ruby
# mbuzz-ruby/lib/mbuzz/client.rb
def track(user_id: nil, visitor_id: nil, event:, properties: {})
  Api.post(EVENTS_PATH, {
    user_id: user_id,
    visitor_id: visitor_id,
    event_type: event,  # ← Change from 'event' to 'event_type'
    properties: properties,
    timestamp: Time.now.utc.iso8601
  })
end
```

**Testing**:
```ruby
# Verify correct parameter name
payload = Mbuzz::Client.new(api_key: 'test').build_event_payload(
  event: 'Signup',
  user_id: 1
)
assert_equal 'Signup', payload[:event_type]
assert_nil payload[:event]
```

---

### 3. Missing API Endpoints 🐛

**Impact**: HIGH - Documented features don't exist

**Current State**:
- Documentation shows: `Mbuzz.identify()` and `Mbuzz.alias()`
- Gem implements: Both methods exist and call `/api/v1/identify` and `/api/v1/alias`
- Backend routes: These endpoints don't exist

**Location**:
- Docs: `app/views/docs/_getting_started.html.erb:208-260`
- Gem: `mbuzz-ruby/lib/mbuzz/client.rb:19-39`
- Routes: `config/routes.rb` (missing)

**Recommendation**: Two options:

#### Option A: Implement Endpoints (Recommended)
Implement the identify and alias endpoints to match Segment's API pattern.

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :events, only: [:create]
    post 'identify', to: 'identify#create'  # ← Add
    post 'alias', to: 'alias#create'        # ← Add
    get 'validate', to: 'validate#show'
    get 'health', to: 'health#show'
  end
end

# app/controllers/api/v1/identify_controller.rb
module Api
  module V1
    class IdentifyController < BaseController
      def create
        result = Users::IdentificationService
          .new(current_account)
          .call(identify_params)

        render json: { success: true }, status: :ok
      end

      private

      def identify_params
        params.permit(:user_id, :visitor_id, traits: {})
      end
    end
  end
end

# app/controllers/api/v1/alias_controller.rb
module Api
  module V1
    class AliasController < BaseController
      def create
        result = Visitors::AliasService
          .new(current_account)
          .call(alias_params)

        render json: { success: true }, status: :ok
      end

      private

      def alias_params
        params.permit(:visitor_id, :user_id)
      end
    end
  end
end
```

**Services to create**:
- `app/services/users/identification_service.rb` - Store user traits
- `app/services/visitors/alias_service.rb` - Link visitor to user

#### Option B: Remove From Docs (Temporary)
Remove identify/alias from docs and gem until implemented.

**Decision**: Implement Option A - these are core features for attribution.

---

### 4. Environment Variable Name Inconsistency ⚠️

**Impact**: MEDIUM - User confusion about which env var to use

**Current State**:
- Getting Started guide uses: `MBUZZ_API_KEY`
- Authentication doc used: `MULTIBUZZ_API_KEY` (fixed)
- Gem uses: `MBUZZ_API_KEY` (in examples)

**Location**:
- Docs (correct): `app/views/docs/_getting_started.html.erb:60, 72`
- Docs (incorrect): `app/views/docs/_authentication.html.erb:111, 123, 162`
- Helpers (correct): `app/helpers/docs_helper.rb:35`

**Fix**:
Standardize on `MBUZZ_API_KEY` everywhere (shorter, matches gem name).

```bash
# Find and replace in authentication doc
# Already fixed - all uses of MULTIBUZZ_API_KEY replaced with MBUZZ_API_KEY
```

**Verification**:
```bash
# Ensure no references to old name
grep -r "MULTIBUZZ_API_KEY" .
# Should return no results (all replaced with MBUZZ_API_KEY)
# Should return no results
```

---

### 5. Gem Specification Uses Wrong Parameter Name ⚠️

**Impact**: LOW - Confusing for gem contributors

**Current State**:
- Gem spec says: `anonymous_id` parameter
- Gem implementation uses: `visitor_id` parameter (correct)
- Backend expects: `visitor_id` (correct)

**Location**:
- Spec (incorrect): `mbuzz-ruby/SPECIFICATION.md:170, 173`
- Gem (correct): `mbuzz-ruby/lib/mbuzz/client.rb:5, 12`

**Fix**:
```markdown
# mbuzz-ruby/SPECIFICATION.md
# Change from:
- anonymous_id - Visitor ID from cookies (required if no user_id)

# Change to:
- visitor_id - Visitor ID from cookies (required if no user_id)
```

---

## Implementation Order

### Phase 1: Fix Gem (Breaking Changes)
1. Fix timestamp format (`Time.now.to_i` → `Time.now.utc.iso8601`)
2. Fix event parameter name (`event:` → `event_type:`)
3. Update SPECIFICATION.md (`anonymous_id` → `visitor_id`)
4. Bump gem version to `0.2.0` (breaking changes)
5. Update README with migration guide

### Phase 2: Fix Backend (New Features)
1. Implement `POST /api/v1/identify` endpoint
2. Implement `POST /api/v1/alias` endpoint
3. Create `Users::IdentificationService`
4. Create `Visitors::AliasService`
5. Add controller tests

### Phase 3: Fix Documentation (Consistency)
1. Standardize `MBUZZ_API_KEY` everywhere
2. Update all code examples to use gem v0.2.0 syntax
3. Add migration guide for existing users

### Phase 4: Testing
1. Manual UAT of full flow: install gem → track event → see in dashboard
2. Test identify flow: track anonymous → identify → track identified
3. Test alias flow: track as visitor → alias to user → verify linkage
4. Verify all curl examples work
5. Test rate limiting works correctly

---

## Success Criteria

- [ ] Gem can track events successfully without errors
- [ ] Backend validates and processes all events correctly
- [ ] Identify and alias endpoints work end-to-end
- [ ] All documentation examples work when copy-pasted
- [x] No references to `MULTIBUZZ_API_KEY` in docs (replaced with MBUZZ_API_KEY)
- [ ] No references to `anonymous_id` in gem spec
- [ ] UAT passes for complete user journey

---

## Risk Assessment

**High Risk**:
- Timestamp format change is a breaking change for existing gem users
- Need migration guide and version bump

**Medium Risk**:
- New endpoints need proper testing for edge cases
- Alias logic needs to handle existing visitor→user links

**Low Risk**:
- Documentation updates are non-breaking
- Parameter name changes are internal to gem

---

## Next Steps

1. Create feature branch: `fix/critical-gem-backend-inconsistencies`
2. Update mbuzz-ruby gem (Phase 1)
3. Test gem changes locally
4. Implement backend endpoints (Phase 2)
5. Update documentation (Phase 3)
6. Run full UAT (Phase 4)
7. Merge to main
8. Release gem v0.2.0
9. Update production docs

---

**Estimated Effort**: 4-6 hours
**Target Completion**: Before UAT begins
