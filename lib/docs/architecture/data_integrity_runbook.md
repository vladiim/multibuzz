# Data Integrity Runbook

**Updated:** 2026-02-09

Diagnosing and repairing session/visitor data integrity issues.

---

## Quick Diagnostics

Run these in `kamal console` to assess data health for an account.

### Ghost Session Check

```ruby
a = Account.find(ACCOUNT_ID)
total = a.sessions.where("started_at > ?", 7.days.ago).count
ghosts = a.sessions.where("started_at > ?", 7.days.ago)
  .where(initial_referrer: [nil, ""])
  .where("initial_utm IS NULL OR initial_utm = '{}'::jsonb")
  .where("click_ids IS NULL OR click_ids = '{}'::jsonb")
  .where("NOT EXISTS (SELECT 1 FROM events WHERE events.session_id = sessions.id)")
  .count
puts "Ghosts: #{ghosts}/#{total} (#{(ghosts.to_f/total*100).round(1)}%)"
```

If ghost % > 50%, sessions are being created on non-navigation requests.

### Self-Referral Check

```ruby
a.sessions.where(channel: "referral").where("started_at > ?", 7.days.ago)
  .group("substring(initial_referrer from '://([^/]+)')")
  .order("count_all DESC").limit(10).count
```

If the top referrer domains are the client's own domains, self-referral misattribution is active.

### Session Inflation Check

```ruby
# Sessions per converting visitor
ActiveRecord::Base.connection.execute(<<~SQL).each do |r|
  SELECT v.visitor_id, COUNT(DISTINCT s.id) as session_count,
    array_agg(DISTINCT s.channel ORDER BY s.channel) as channels
  FROM visitors v
  JOIN events e ON e.visitor_id = v.id AND e.account_id = #{a.id} AND e.event_type = 'add_to_cart'
  JOIN sessions s ON s.visitor_id = v.id AND s.account_id = #{a.id}
  WHERE v.account_id = #{a.id} AND e.occurred_at > NOW() - INTERVAL '7 days'
  GROUP BY v.visitor_id ORDER BY session_count DESC LIMIT 10
SQL
  puts "visitor=#{r['visitor_id']&.truncate(20)} | sessions=#{r['session_count']} | channels=#{r['channels']}"
end
```

If converting visitors have 10+ sessions across multiple channels, session continuity is broken.

### Conversion Attribution Check

```ruby
# Compare conversion session vs landing session
ActiveRecord::Base.connection.execute(<<~SQL).each do |r|
  SELECT c.id, cs.channel as conv_ch, fs.channel as land_ch,
    cs.initial_referrer as conv_ref, fs.initial_referrer as land_ref
  FROM conversions c
  JOIN sessions cs ON cs.id = c.session_id
  JOIN LATERAL (
    SELECT * FROM sessions WHERE visitor_id = cs.visitor_id AND account_id = #{a.id}
    ORDER BY started_at ASC LIMIT 1
  ) fs ON true
  WHERE c.account_id = #{a.id} AND c.created_at > NOW() - INTERVAL '7 days'
  LIMIT 20
SQL
  puts "conv=#{r['id']} | conv_ch=#{r['conv_ch']} | land_ch=#{r['land_ch']} | conv_ref=#{r['conv_ref']&.truncate(50)} | land_ref=#{r['land_ref']&.truncate(50)}"
end
```

If `conv_ch=referral` but `land_ch=paid_search`, conversions are linking to the wrong session.

### Ghost Session Rate (Hourly Trend)

```ruby
ActiveRecord::Base.connection.execute(<<~SQL).each do |r|
  SELECT date_trunc('hour', started_at) as hour, COUNT(*) as total,
    COUNT(*) FILTER (WHERE NOT EXISTS (
      SELECT 1 FROM events WHERE events.session_id = sessions.id
    )) as ghosts
  FROM sessions WHERE account_id = #{a.id} AND started_at > NOW() - INTERVAL '48 hours'
  GROUP BY 1 ORDER BY 1 DESC
SQL
  pct = r['total'].to_i > 0 ? (r['ghosts'].to_f / r['total'] * 100).round(1) : 0
  puts "#{r['hour']} | total=#{r['total']} | ghosts=#{r['ghosts']} (#{pct}%)"
end
```

Look for a drop in ghost rate after SDK deployment or server-side session continuity fix.

---

## Known Bugs & Fixes

### Bug 1: Session Inflation (every request creates new session)

**Cause**: SDK v0.7.0+ removed session cookie. Each request sends `session_id: SecureRandom.uuid`. Server's `find_or_initialize_session` never matches the UUID, always creates new. The 30-second fingerprint dedup only catches concurrent requests.

**Fix (server)**: Session continuity — `CreationService` reuses active sessions (30-min window) for internal navigation. New sessions only for new traffic sources (UTM, click_ids, external referrer). See `lib/specs/session_continuity_spec.md`.

**Fix (SDK)**: v0.7.3 navigation detection should filter non-navigation requests. Currently broken — likely `Sec-Fetch-*` headers stripped by reverse proxy.

### Bug 2: Conversion Misattribution (links to wrong session)

**Cause**: Consequence of Bug 1. Event resolution picks the most recently active session (`ResolutionService`). If internal navigation created a new session between landing and conversion, the event links to that session instead of the landing session.

**Fix**: Addressed by Bug 1 fix. With session continuity, there's only one session per visit, so events/conversions automatically link to the landing session.

### Bug 3: Self-Referral Channel ("referral" instead of "direct")

**Cause**: When `page_host` is nil, `internal_referrer?` returns false, and same-domain referrers fall through to "referral". Belt-and-suspenders `host_from_referrer` fallback added.

**Note**: With session continuity fix, internal navigation reuses existing session (no new session created), so self-referral sessions are largely eliminated. The `host_from_referrer` fallback handles edge cases.

### Bug 4: No Page View Events

**Cause**: Client only tracks `add_to_cart`. No `page_view` events. Funnel "Visits" counts sessions.

**Fix**: Client integration gap. Once ghost sessions are eliminated, session count becomes a reasonable proxy for visits.

---

## Repair Procedures

### Full Repair (after session continuity fix is deployed)

```bash
# 1. Preview all changes
bin/rails data_repair:purge_ghost_sessions ACCOUNT_ID=123 DRY_RUN=true SINCE_DAYS=90
bin/rails visitors:deduplicate ACCOUNT_ID=123 DRY_RUN=true SINCE_DAYS=90

# 2. Execute
bin/rails data_repair:purge_ghost_sessions ACCOUNT_ID=123 DRY_RUN=false SINCE_DAYS=90
bin/rails visitors:deduplicate ACCOUNT_ID=123 DRY_RUN=false SINCE_DAYS=90
bin/rails attribution:backfill_channels ACCOUNT_ID=123
```

### Conversion Reattribution (after session continuity fix)

Conversions linked to self-referral sessions need reattribution to their visitor's landing session:

```ruby
# Preview
a = Account.find(ACCOUNT_ID)
bad = a.conversions.joins(:session).where(sessions: { channel: 'referral' })
  .where("conversions.created_at > ?", 90.days.ago)
puts "Conversions to reattribute: #{bad.count}"

# Execute (after validation)
bad.find_each do |c|
  landing = a.sessions.where(visitor_id: c.visitor_id).order(:started_at).first
  next unless landing && landing.id != c.session_id
  c.update_columns(session_id: landing.id)
end
```

---

## Service Reference

| Service | Purpose |
|---------|---------|
| `DataRepair::GhostSessionPurgeService` | Deletes sessions with 0 events, nil referrer, empty UTM, empty click_ids |
| `DataRepair::SelfReferralFixService` | Changes channel from "referral" to "direct" for sessions where referrer matches internal domains |
| `Visitors::DeduplicationService` | Merges duplicate visitors created by concurrent sub-requests |

All services support `dry_run: true` (default) and `since_days:` parameter.

---

## Related Specs

- `lib/specs/session_continuity_spec.md` — Session continuity fix (P0)
- `lib/specs/api_data_integrity_spec.md` — API-level data corruption fixes
- `lib/specs/incidents/2026-01-29-visit-count-inflation-5x.md` — Original Turbo inflation incident
