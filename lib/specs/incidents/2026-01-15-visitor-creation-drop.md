# Incident Report: Visitor Creation Drop (2026-01-15)

## Summary

Conversion tracking dropped ~80% after the `require_existing_visitor` change went live around January 11, 2026. Only 10 of 47 conversions were tracked on January 14.

## Timeline

- **Jan 11**: `require_existing_visitor` change deployed to production
- **Jan 11-14**: Visitor creation dropped from ~11,000/day to ~200/day
- **Jan 15**: Issue identified and fixed

## Symptoms

- Conversions rejected with "visitor not found" errors
- Events failing validation due to missing visitors
- Database showed dramatic visitor creation drop:

```sql
Visitor.where("created_at > ?", 7.days.ago)
       .group("DATE(created_at)")
       .count
       .sort_by(&:first)

# Results:
# 2026-01-09 => 11,234
# 2026-01-10 => 10,892
# 2026-01-11 => 847    # <-- Drop starts
# 2026-01-12 => 203
# 2026-01-13 => 198
# 2026-01-14 => 212
```

## Root Cause

**pet_resorts was running mbuzz-ruby gem version 0.6.2 instead of 0.7.1.**

Evidence from server logs:
```
User-Agent: mbuzz-ruby/0.6.2
```

But Gemfile specified:
```ruby
gem 'mbuzz', '~> 0.7.1'
```

The session creation middleware that calls `POST /api/v1/sessions` (which creates visitors server-side) was added/fixed in a version after 0.6.2. Without this call, visitors were never created, so the `require_existing_visitor` check rejected all events.

## Investigation Path

1. Initial hypothesis: SDKs not calling `/sessions` endpoint
2. Code review of mbuzz-ruby showed middleware DOES call `/sessions`
3. Server logs showed requests hitting `/sessions` with 202 status
4. Version mismatch discovered: logs showed 0.6.2, Gemfile showed 0.7.1
5. Verified version is dynamic (not hardcoded) via gemspec analysis:
   - `lib/mbuzz/version.rb` defines `VERSION = "0.7.1"`
   - `lib/mbuzz/api.rb` uses `request["User-Agent"] = "mbuzz-ruby/#{VERSION}"`
   - Confirmed pet_resorts deployment was stale

## Resolution

Deployed pet_resorts with updated mbuzz gem (0.7.1).

## Key Architecture Points

Sessions are managed **SERVER-SIDE**, not by SDKs:

1. SDK middleware calls `POST /api/v1/sessions` for new visitors
2. Server creates visitor record and resolves/creates session using device fingerprint
3. Device fingerprint = `SHA256(ip|user_agent)[0:32]`
4. Server manages 30-minute sliding window via `last_activity_at`
5. SDKs only manage visitor cookie (`_mbuzz_vid`), NOT session cookie

## Lessons Learned

1. Version verification should be part of deployment checklist
2. `require_existing_visitor` change needed coordinated SDK deployments
3. Server logs showing SDK version helped identify the issue quickly

## Related Files

- `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/middleware/tracking.rb` - Session creation middleware
- `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/client/session_request.rb` - Session API client
- `/Users/vlad/code/m/multibuzz/app/services/sessions/creation_service.rb` - Server-side session creation
