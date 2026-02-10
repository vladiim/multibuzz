# Session Continuity — Micro-Test, Rollout & Validation Plan

**Date:** 2026-02-10
**Depends on:** `lib/specs/session_continuity_spec.md` (implementation complete)
**Branch:** `feature/e1s4-content`

---

## Part 1: Micro-Test (Prove The Fix Before Deploying)

Before deploying a single line of code, we simulate the fix against live data to prove the impact is what we expect. This is a read-only exercise using production console queries.

### 1.1 Pick A Converting Visitor With The Bug

Find a visitor who has a conversion attributed to "referral" where their first session was actually from search:

```ruby
a = Account.find(2)

sql = "
  SELECT c.id AS conv_id, c.visitor_id, c.session_id AS conv_session_id,
    cs.channel AS conv_channel, cs.initial_referrer AS conv_ref,
    fs.id AS landing_session_id, fs.channel AS landing_channel,
    fs.initial_utm AS landing_utm, fs.initial_referrer AS landing_ref,
    (SELECT COUNT(*) FROM sessions WHERE visitor_id = c.visitor_id AND account_id = #{a.id}) AS total_sessions
  FROM conversions c
  JOIN sessions cs ON cs.id = c.session_id
  JOIN LATERAL (
    SELECT * FROM sessions WHERE visitor_id = cs.visitor_id AND account_id = #{a.id}
    ORDER BY started_at ASC LIMIT 1
  ) fs ON true
  WHERE c.account_id = #{a.id}
    AND cs.channel = 'referral'
    AND fs.channel IN ('paid_search', 'organic_search')
    AND c.created_at > NOW() - INTERVAL '30 days'
  LIMIT 1
"
candidate = ActiveRecord::Base.connection.execute(sql).first
puts candidate.inspect
```

**Expected:** A visitor with 100+ sessions where the conversion session is "referral" but the landing session is "paid_search" or "organic_search".

### 1.2 Map The Visitor's Full Session Timeline

```ruby
vid = candidate['visitor_id']
sessions = a.sessions.where(visitor_id: vid).order(:started_at)
  .pluck(:id, :session_id, :channel, :initial_referrer, :started_at, :last_activity_at, :device_fingerprint)

puts "Total sessions: #{sessions.size}"
sessions.each_with_index do |s, i|
  id, sid, ch, ref, start, last, fp = s
  gap = i > 0 ? (start - sessions[i-1][4]).round(1) : 0
  puts "#{'%3d' % (i+1)} | #{id} | #{ch&.ljust(15)} | ref=#{ref&.truncate(40)&.ljust(42)} | gap=#{gap}s | fp=#{fp&.first(8)}"
end
```

**What to look for:**
- Session 1 has the real traffic source (paid_search with Google UTM)
- Sessions 2-N are ghost sessions created seconds apart, most with self-referral channel
- The conversion session is somewhere deep in the list, not session 1

### 1.3 Simulate The Fix: Which Sessions Would Survive?

Apply the session continuity logic retroactively — which sessions would have been created vs reused?

```ruby
# Simulate: walk through sessions chronologically, apply continuity rules
fp = sessions.first[6] # device_fingerprint from first session
surviving = []
active_session = nil

sessions.each do |id, sid, ch, ref, start, last, session_fp|
  # Skip sessions with different fingerprints
  if session_fp != fp
    surviving << { id: id, channel: ch, reason: "different_fingerprint" }
    active_session = { id: id, last_activity: last }
    next
  end

  # Check if active session exists within 30 min window
  if active_session && (start - active_session[:last_activity]) < 30.minutes
    # Would this be a new traffic source?
    has_utm = a.sessions.find(id).initial_utm&.values&.any?(&:present?) rescue false
    has_click_ids = a.sessions.find(id).click_ids&.any? rescue false

    ref_host = ref.present? ? (URI.parse(ref).host rescue nil) : nil
    page_host = a.sessions.find(id).events.first&.properties&.dig("host")
    is_external = ref_host.present? && page_host.present? &&
      ref_host.downcase.sub(/^www\./, "") != page_host.downcase.sub(/^www\./, "")

    if has_utm || has_click_ids || is_external
      surviving << { id: id, channel: ch, reason: "new_traffic_source" }
      active_session = { id: id, last_activity: last }
    else
      # This session would be REUSED (not created) — it's a ghost
      active_session[:last_activity] = [active_session[:last_activity], start].max
    end
  else
    # Session timeout or first session
    surviving << { id: id, channel: ch, reason: active_session ? "timeout_30m" : "first_session" }
    active_session = { id: id, last_activity: last }
  end
end

puts "\n=== SIMULATION RESULT ==="
puts "Before: #{sessions.size} sessions"
puts "After:  #{surviving.size} sessions (#{((1 - surviving.size.to_f / sessions.size) * 100).round(1)}% reduction)"
puts "\nSurviving sessions:"
surviving.each do |s|
  puts "  #{s[:id]} | #{s[:channel]&.ljust(15)} | #{s[:reason]}"
end
```

**Expected:** 90%+ reduction. Surviving sessions should be the landing session + any with genuine new traffic sources (e.g., email click, new Google ad).

### 1.4 Simulate Reattribution

With the surviving sessions identified, what would the conversion attribution look like?

```ruby
conv = a.conversions.find(candidate['conv_id'])
surviving_ids = surviving.map { |s| s[:id] }

# Current attribution
puts "=== CURRENT ATTRIBUTION ==="
conv.attribution_credits.includes(:attribution_model).each do |credit|
  sess = Session.find(credit.session_id)
  puts "  #{credit.attribution_model.name}: #{credit.channel} (#{(credit.credit * 100).round(1)}%) — session #{sess.channel}"
end

# What it WOULD be with only surviving sessions
puts "\n=== PROJECTED ATTRIBUTION (surviving sessions only) ==="
journey = a.sessions.where(id: surviving_ids)
  .where("started_at <= ?", conv.converted_at)
  .where("started_at >= ?", conv.converted_at - 30.days)
  .where.not(channel: nil)
  .order(:started_at)

journey.each_with_index do |s, i|
  first_touch = i == 0 ? "← FIRST" : ""
  last_touch = i == journey.size - 1 ? "← LAST" : ""
  puts "  #{s.channel.ljust(15)} | #{s.initial_utm&.slice('utm_source', 'utm_campaign')&.compact} #{first_touch} #{last_touch}"
end

puts "\nFirst-touch: #{journey.first&.channel}"
puts "Last-touch:  #{journey.last&.channel}"
```

**Expected:** First-touch = `paid_search` (was `referral`). Last-touch = `paid_search` or whatever the real last traffic source was (not self-referral).

### 1.5 Scale The Micro-Test To All Conversions

```ruby
# Count how many conversions would change attribution
total = a.conversions.where("created_at > ?", 30.days.ago).count

sql = "
  SELECT COUNT(*) FROM conversions c
  JOIN sessions cs ON cs.id = c.session_id
  JOIN LATERAL (
    SELECT channel FROM sessions WHERE visitor_id = cs.visitor_id AND account_id = #{a.id}
    ORDER BY started_at ASC LIMIT 1
  ) fs ON true
  WHERE c.account_id = #{a.id}
    AND c.created_at > NOW() - INTERVAL '30 days'
    AND cs.channel != fs.channel
"
misattributed = ActiveRecord::Base.connection.execute(sql).first['count']

puts "Total conversions (30d): #{total}"
puts "Misattributed (conv_ch != landing_ch): #{misattributed} (#{(misattributed.to_f / total * 100).round(1)}%)"

# Channel shift projection
puts "\nProjected channel shift (conversion sessions → landing sessions):"
sql = "
  SELECT cs.channel AS from_channel, fs.channel AS to_channel, COUNT(*) AS count
  FROM conversions c
  JOIN sessions cs ON cs.id = c.session_id
  JOIN LATERAL (
    SELECT channel FROM sessions WHERE visitor_id = cs.visitor_id AND account_id = #{a.id}
    ORDER BY started_at ASC LIMIT 1
  ) fs ON true
  WHERE c.account_id = #{a.id}
    AND c.created_at > NOW() - INTERVAL '30 days'
    AND cs.channel != fs.channel
  GROUP BY cs.channel, fs.channel
  ORDER BY count DESC
"
ActiveRecord::Base.connection.execute(sql).each do |r|
  puts "  #{r['from_channel']&.ljust(15)} → #{r['to_channel']&.ljust(15)} : #{r['count']}"
end
```

**Expected:**
- 60-80% of conversions are misattributed
- Biggest shift: `referral → paid_search` and `referral → organic_search`
- This is the "before vs after" proof for the client

---

## Part 2: Rollout Plan

### Why Not Feature Flags?

We don't have feature flag infrastructure, and adding one for this specific change would be over-engineering. The change is in a hot path (`CreationService`) that runs on every SDK request. Instead:

1. The fix only affects **new sessions going forward** — it doesn't retroactively change existing data
2. We can validate immediately by comparing the last-hour ghost rate to historical rates
3. If something goes wrong, we revert the deploy (Kamal rollback is fast)
4. Historical data repair is a separate, controlled operation using existing rake tasks

### Rollout Phases

#### Phase 0: Pre-Deploy Baseline (before deploy)

Capture current metrics in production console. These are our "before" numbers.

```ruby
a = Account.find(2)
baseline = {}

# Ghost session rate (24h)
total_24h = a.sessions.where("started_at > ?", 24.hours.ago).count
ghosts_24h = a.sessions.where("started_at > ?", 24.hours.ago)
  .where(initial_referrer: [nil, ""])
  .where("initial_utm IS NULL OR initial_utm = '{}'::jsonb")
  .where("click_ids IS NULL OR click_ids = '{}'::jsonb")
  .where("NOT EXISTS (SELECT 1 FROM events WHERE events.session_id = sessions.id)")
  .count
baseline[:ghost_rate] = (ghosts_24h.to_f / total_24h * 100).round(1)

# Sessions per converting visitor (7d)
sql = "
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY session_count) AS median
  FROM (
    SELECT COUNT(DISTINCT s.id) AS session_count
    FROM conversions c
    JOIN sessions s ON s.visitor_id = c.visitor_id AND s.account_id = #{a.id}
    WHERE c.account_id = #{a.id} AND c.created_at > NOW() - INTERVAL '7 days'
    GROUP BY c.visitor_id
  ) sub
"
baseline[:sessions_per_converter] = ActiveRecord::Base.connection.execute(sql).first['median']

# Channel distribution (7d conversions)
baseline[:channel_dist] = a.conversions.joins(:session)
  .where("conversions.created_at > ?", 7.days.ago)
  .group("sessions.channel").count

# Attribution model outputs (latest)
a.attribution_models.active.each do |model|
  credits = model.attribution_credits.where("created_at > ?", 7.days.ago)
  baseline[:"#{model.algorithm}_credits"] = credits.group(:channel)
    .sum(:credit)
    .transform_values { |v| v.round(2) }
end

puts "=== BASELINE (pre-deploy) ==="
puts JSON.pretty_generate(baseline)
```

Save this output — it's the reference for all post-deploy comparisons.

#### Phase 1: Deploy + 1 Hour Validation

Deploy to production via Kamal. The fix only affects new session creation requests — no migration, no data change.

```bash
kamal deploy
```

**T+15 minutes:** First ghost rate check.

```ruby
a = Account.find(2)

# Compare last 15 min to same period yesterday
now_sessions = a.sessions.where("started_at > ?", 15.minutes.ago).count
now_ghosts = a.sessions.where("started_at > ?", 15.minutes.ago)
  .where(initial_referrer: [nil, ""])
  .where("initial_utm IS NULL OR initial_utm = '{}'::jsonb")
  .where("click_ids IS NULL OR click_ids = '{}'::jsonb")
  .where("NOT EXISTS (SELECT 1 FROM events WHERE events.session_id = sessions.id)")
  .count
now_rate = now_sessions > 0 ? (now_ghosts.to_f / now_sessions * 100).round(1) : 0

yday_sessions = a.sessions.where("started_at BETWEEN ? AND ?", 24.hours.ago - 15.minutes, 24.hours.ago).count
yday_ghosts = a.sessions.where("started_at BETWEEN ? AND ?", 24.hours.ago - 15.minutes, 24.hours.ago)
  .where(initial_referrer: [nil, ""])
  .where("initial_utm IS NULL OR initial_utm = '{}'::jsonb")
  .where("click_ids IS NULL OR click_ids = '{}'::jsonb")
  .where("NOT EXISTS (SELECT 1 FROM events WHERE events.session_id = sessions.id)")
  .count
yday_rate = yday_sessions > 0 ? (yday_ghosts.to_f / yday_sessions * 100).round(1) : 0

puts "Ghost rate: now=#{now_rate}% vs yesterday=#{yday_rate}%"
puts "Session volume: now=#{now_sessions} vs yesterday=#{yday_sessions}"
```

**Pass criteria:**
| Metric | Before | Expected After | Rollback If |
|--------|--------|----------------|-------------|
| Ghost session rate | ~98% | < 10% | > 50% |
| New sessions/hour | ~1500 | ~100-300 | 0 or > 2000 |
| Events still tracked | ~20/hour | ~20/hour (unchanged) | 0 |
| Conversions still tracked | ~5/hour | ~5/hour (unchanged) | 0 |

**T+1 hour:** Full validation.

```ruby
a = Account.find(2)

# 1. Ghost rate (last hour)
puts "--- Ghost Rate ---"
total = a.sessions.where("started_at > ?", 1.hour.ago).count
ghosts = a.sessions.where("started_at > ?", 1.hour.ago)
  .where(initial_referrer: [nil, ""])
  .where("initial_utm IS NULL OR initial_utm = '{}'::jsonb")
  .where("click_ids IS NULL OR click_ids = '{}'::jsonb")
  .where("NOT EXISTS (SELECT 1 FROM events WHERE events.session_id = sessions.id)")
  .count
puts "#{ghosts}/#{total} (#{total > 0 ? (ghosts.to_f / total * 100).round(1) : 0}%)"

# 2. Session reuse happening?
puts "\n--- Session Reuse Evidence ---"
reused = a.sessions.where("started_at > ?", 1.hour.ago)
  .where("last_activity_at > started_at + interval '1 minute'")
  .count
puts "Sessions with activity > 1 min after start: #{reused}/#{total}"

# 3. Channel distribution (last hour sessions)
puts "\n--- Channel Distribution (last hour) ---"
a.sessions.where("started_at > ?", 1.hour.ago).group(:channel).count
  .sort_by { |_, v| -v }.each { |ch, ct| puts "  #{ch&.ljust(15)}: #{ct}" }

# 4. Events and conversions still flowing?
puts "\n--- Event/Conversion Flow ---"
puts "Events (last hour): #{a.events.where('occurred_at > ?', 1.hour.ago).count}"
puts "Conversions (last hour): #{a.conversions.where('created_at > ?', 1.hour.ago).count}"

# 5. No errors in logs?
puts "\n--- Check server logs for errors ---"
puts "Run: kamal app logs --since 1h | grep -i error | tail -20"
```

**Rollback procedure:**
```bash
kamal rollback
```

Kamal keeps the previous container image. Rollback is instant. No data migration to reverse — the only difference is whether new sessions reuse active ones.

#### Phase 2: T+24 Hours — Attribution Impact

After 24 hours of clean data accumulation, compare attribution model outputs:

```ruby
a = Account.find(2)
puts "=== ATTRIBUTION COMPARISON ==="

a.attribution_models.active.each do |model|
  puts "\n--- #{model.name} (#{model.algorithm}) ---"

  post_credits = model.attribution_credits
    .where("created_at > ?", 24.hours.ago)
    .group(:channel).sum(:credit)
    .transform_values { |v| v.round(2) }

  pre_credits = model.attribution_credits
    .where("created_at BETWEEN ? AND ?", 48.hours.ago, 24.hours.ago)
    .group(:channel).sum(:credit)
    .transform_values { |v| v.round(2) }

  all_channels = (pre_credits.keys + post_credits.keys).uniq.sort
  all_channels.each do |ch|
    pre = pre_credits[ch] || 0
    post = post_credits[ch] || 0
    delta = post - pre
    pct = pre > 0 ? ((delta / pre) * 100).round(1) : "new"
    puts "  #{ch.ljust(15)} | pre: #{pre.to_s.rjust(8)} | post: #{post.to_s.rjust(8)} | delta: #{delta > 0 ? '+' : ''}#{delta.round(2)} (#{pct}%)"
  end
end
```

**Expected shifts across ALL attribution models:**

| Channel | Before (estimated) | After (expected) | Why |
|---------|-------------------|------------------|-----|
| referral | ~60-70% of credit | ~10-15% | Self-referral sessions eliminated |
| paid_search | ~5-10% | ~30-40% | Conversions now link to landing session |
| organic_search | ~5-10% | ~25-35% | Same — landing session preserved |
| direct | ~10% | ~10-15% | Slight increase (some "referral" was actually direct) |
| email | ~2% | ~5% | Real email clicks now survive as sessions |

The shift should be consistent across first-touch, last-touch, linear, time-decay, u-shaped — because the underlying session data is what changed, not the algorithm logic.

**For probabilistic models (Markov, Shapley):** These recalculate based on ALL historical conversion paths. They will shift more gradually as the ratio of clean-to-dirty data improves over days/weeks. Or we can accelerate this with the historical data repair in Phase 4.

#### Phase 3: T+7 Days — Steady State Confirmation

```ruby
a = Account.find(2)
puts "=== 7-DAY STEADY STATE ==="

# Ghost rate trend
7.downto(0) do |d|
  day_start = d.days.ago.beginning_of_day
  day_end = d.days.ago.end_of_day
  total = a.sessions.where(started_at: day_start..day_end).count
  ghosts = a.sessions.where(started_at: day_start..day_end)
    .where(initial_referrer: [nil, ""])
    .where("initial_utm IS NULL OR initial_utm = '{}'::jsonb")
    .where("click_ids IS NULL OR click_ids = '{}'::jsonb")
    .where("NOT EXISTS (SELECT 1 FROM events WHERE events.session_id = sessions.id)")
    .count
  rate = total > 0 ? (ghosts.to_f / total * 100).round(1) : 0
  puts "  #{day_start.to_date} | sessions=#{total.to_s.rjust(5)} | ghosts=#{ghosts.to_s.rjust(5)} (#{rate}%)"
end

# Sessions per converting visitor trend
puts "\n--- Sessions Per Converter (daily median) ---"
7.downto(0) do |d|
  day_start = d.days.ago.beginning_of_day
  day_end = d.days.ago.end_of_day
  sql = "
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sc) AS median,
           AVG(sc) AS mean, MAX(sc) AS max
    FROM (
      SELECT COUNT(DISTINCT s.id) AS sc
      FROM conversions c
      JOIN sessions s ON s.visitor_id = c.visitor_id AND s.account_id = #{a.id}
        AND s.started_at BETWEEN '#{day_start.iso8601}' AND '#{day_end.iso8601}'
      WHERE c.account_id = #{a.id}
        AND c.created_at BETWEEN '#{day_start.iso8601}' AND '#{day_end.iso8601}'
      GROUP BY c.visitor_id
    ) sub
  "
  result = ActiveRecord::Base.connection.execute(sql).first
  puts "  #{day_start.to_date} | median=#{result['median']&.round(1)} | mean=#{result['mean']&.round(1)} | max=#{result['max']}"
end

# Funnel ratio sanity
puts "\n--- Funnel Sanity ---"
visits_7d = a.sessions.where("started_at > ?", 7.days.ago).where.not(channel: nil).count
events_7d = a.events.where("occurred_at > ?", 7.days.ago).count
convs_7d = a.conversions.where("created_at > ?", 7.days.ago).count
puts "Visits: #{visits_7d} | Events: #{events_7d} | Conversions: #{convs_7d}"
puts "Event/Visit ratio: #{(events_7d.to_f / visits_7d).round(2)}"
puts "Conv/Visit ratio:  #{(convs_7d.to_f / visits_7d * 100).round(2)}%"
```

**Pass criteria for steady state:**
- Ghost rate stable < 10% for 7 consecutive days
- Median sessions per converter: 1-3 (was 100+)
- Event/visit ratio > 0.5 (events per real session, not per ghost)
- No unexplained drops in event or conversion volume

#### Phase 4: Historical Data Repair

Only after Phase 3 confirms the fix is stable. This is the destructive phase — modifying existing data.

**Order matters.** Each step depends on the previous:

```
Step 1: Purge ghost sessions         → removes noise
Step 2: Deduplicate visitors         → merges duplicates
Step 3: Backfill session channels    → fixes self-referral → direct
Step 4: Reattribute conversions      → recalculates all attribution credits
Step 5: Rerun attribution models     → updates Markov/Shapley with clean paths
```

**Step 1: Ghost session purge**

Ghost sessions have 0 events, nil referrer, empty UTM, empty click_ids. They serve no purpose.

```bash
# Preview
bin/rails data_repair:purge_ghost_sessions ACCOUNT_ID=2 DRY_RUN=true SINCE_DAYS=90

# Execute (after reviewing preview)
bin/rails data_repair:purge_ghost_sessions ACCOUNT_ID=2 DRY_RUN=false SINCE_DAYS=90
```

*Note: `GhostSessionPurgeService` needs to be created — it doesn't exist yet. See implementation task below.*

**Step 2: Visitor deduplication**

```bash
# Preview
bin/rails visitors:deduplicate ACCOUNT_ID=2 DRY_RUN=true SINCE_DAYS=90

# Execute
bin/rails visitors:deduplicate ACCOUNT_ID=2 DRY_RUN=false SINCE_DAYS=90
```

**Step 3: Fix self-referral channels**

```bash
# Preview
bin/rails attribution:fix_internal_referrers ACCOUNT_ID=2 DRY_RUN=true

# Execute
bin/rails attribution:fix_internal_referrers ACCOUNT_ID=2 DRY_RUN=false
```

**Step 4: Reattribute conversions**

```bash
# This recalculates all attribution credits using the cleaned session data
bin/rails attribution:reattribute_conversions ACCOUNT_ID=2 DRY_RUN=false
```

**Step 5: Rerun attribution models**

Increment each model's version to mark all existing credits as stale, then trigger rerun:

```ruby
a = Account.find(2)
a.attribution_models.active.each do |model|
  model.increment!(:version)
  Attribution::RerunJob.perform_later(model.id)
  puts "Queued rerun for #{model.name} (v#{model.version})"
end
```

**Post-repair validation:**

```ruby
a = Account.find(2)

puts "=== POST-REPAIR ATTRIBUTION ==="
a.attribution_models.active.each do |model|
  puts "\n--- #{model.name} ---"
  model.attribution_credits.where("created_at > ?", 90.days.ago)
    .group(:channel).sum(:credit)
    .sort_by { |_, v| -v }
    .each { |ch, cr| puts "  #{ch.ljust(15)}: #{cr.round(2)}" }
end

# Funnel numbers should make sense now
visits = a.sessions.where("started_at > ?", 90.days.ago).where.not(channel: nil).count
convs = a.conversions.where("created_at > ?", 90.days.ago).count
puts "\n90-day visits: #{visits} (was ~73k, expect ~15-20k)"
puts "90-day conversions: #{convs} (should be unchanged)"
puts "Conversion rate: #{(convs.to_f / visits * 100).round(2)}% (was ~0.5%, expect ~2-3%)"
```

---

## Part 3: Implementation Tasks (For Repair Only)

The session continuity fix is already implemented. These tasks are for the historical data repair tooling:

- [ ] **R.1** Create `DataRepair::GhostSessionPurgeService` — deletes sessions with 0 events + nil referrer + empty UTM + empty click_ids. Supports `dry_run`, `since_days`.
- [ ] **R.2** Create `data_repair:purge_ghost_sessions` rake task (wrapper around service)
- [ ] **R.3** Add `before_destroy` check on Session — prevent deleting sessions with events/conversions (safety net)

---

## Rollback Decision Matrix

| Signal | Severity | Action |
|--------|----------|--------|
| Ghost rate still > 50% after 15 min | High | Check server logs. If errors → rollback. If just slow propagation → wait 30 min. |
| Events/conversions dropping to 0 | Critical | Rollback immediately. Check `require_existing_visitor` interactions. |
| New sessions/hour = 0 | Critical | Rollback. Session creation is completely broken. |
| New sessions/hour > baseline | Low | Expected if fix isn't active (bad deploy). Re-deploy. |
| Ghost rate 10-30% (not <10%) | Medium | Acceptable. Some ghosts expected from non-navigation SDK calls (identify, background jobs). Monitor. |
| Attribution hasn't shifted after 24h | Low | Expected — only new conversions get clean data. Historical repair needed. |
| Markov/Shapley outputs unchanged | Low | Expected — they use historical paths. Will shift after Phase 4 repair. |

---

## Success Criteria

The fix is validated when ALL of these hold for 7+ days:

| Metric | Target | Measurement |
|--------|--------|-------------|
| Ghost session rate | < 10% | Phase 1 query |
| Sessions per converting visitor (median) | 1-3 | Phase 3 query |
| Conversion channel = landing channel | > 80% match | Phase 2 query |
| Event volume | Within 10% of baseline | Phase 1 query |
| Conversion volume | Within 10% of baseline | Phase 1 query |
| No error spikes in logs | 0 new error types | `kamal app logs` |

After historical repair (Phase 4):

| Metric | Target | Measurement |
|--------|--------|-------------|
| 90-day visit count | ~15-20k (was 73k) | `sessions.where.not(channel: nil).count` |
| 90-day conversion rate | ~2-3% (was ~0.5%) | `conversions.count / sessions.count` |
| referral channel share | < 15% (was ~60%) | Attribution credit breakdown |
| paid_search + organic_search share | > 50% (was ~15%) | Attribution credit breakdown |
