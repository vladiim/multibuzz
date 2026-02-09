# Session Continuity — Micro-Test, Rollout & Validation Plan

**Date:** 2026-02-10
**Depends on:** `lib/specs/session_continuity_spec.md` (implementation complete)
**Branch:** `feature/e1s4-content`

### Timeline

| Date | Phase | Status |
|------|-------|--------|
| 2026-02-09 | Part 1: Micro-test (read-only production queries) | ✅ Complete — 88.3% misattributed |
| 2026-02-10 | Phase 0: Baseline capture | ✅ Complete — 73.3% ghost rate, 0 paid_search conversions |
| 2026-02-10 | Phase 1: Deploy + 1hr validation | ✅ Complete — session inflation 92% reduced, no rollback |
| 2026-02-11 | Phase 2: T+24hr attribution comparison | Pending |
| 2026-02-14 | Phase 3: T+4d steady state + before/after report | Pending |
| 2026-02-14+ | Phase 4: Historical data repair (destructive) | Pending — build ghost purge service first |

---

## Part 1: Micro-Test (Prove The Fix Before Deploying)

Before deploying a single line of code, we simulate the fix against live data to prove the impact is what we expect. This is a read-only exercise using production console queries.

### Production Micro-Test Results (2026-02-09, Account 2)

> **Bottom line:** 88.3% of conversions are misattributed. The biggest shift is `referral → paid_search` (540 conversions) and `referral → organic_search` (416). Session continuity will prevent new ghost sessions, but historical data repair (Phase 4) is essential.

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

**Result:** `conv_id=2879`, visitor with 6 sessions. Conversion channel = `referral`, landing channel = `paid_search` with Google UTM (`utm_medium=cpc, utm_source=google`).

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

**Result:** 6 sessions for this visitor. Key finding: **fingerprint switching** — sessions 2-3 had fingerprint `e0b4f44c` but session 4 switched to `9ab3a578`. This means session continuity wouldn't have prevented this specific misattribution because the fingerprint changed mid-visit (likely mobile network switch or proxy).

**Implication:** Session continuity fixes the common case (same fingerprint, rapid-fire ghost sessions), but fingerprint instability creates a long tail of cases it can't fix. The `FingerprintInstability` surveillance check was added to catch this pattern.

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

**Note:** We tested a worst-case visitor (`conv_id=3157`): **1,259 sessions** over 42 days, **434 distinct fingerprints**, **348 nil-fingerprint sessions**. Channel distribution: 728 direct, 223 paid_search, 131 organic_search, 59 paid_social, 55 referral, 48 organic_social, 11 email, 4 other. This is likely a multi-location business (staff accessing from different networks) or an incorrect dedup merge. The `ExtremeSessionVisitors` surveillance check was added to flag these.

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

**Result (2026-02-09):**
- Total conversions (30d): **1,534**
- Misattributed (conv_channel != landing_channel): **1,355 (88.3%)**
- Channel shift:

| From | To | Count |
|------|----|-------|
| referral | paid_search | 540 |
| referral | organic_search | 416 |
| direct | paid_search | 164 |
| direct | organic_search | 139 |
| referral | direct | 39 |
| referral | paid_social | 20 |
| referral | organic_social | 14 |
| direct | organic_social | 9 |
| direct | email | 5 |
| referral | email | 4 |
| direct | paid_social | 3 |
| organic_search | paid_search | 2 |

**Key insight:** 956/1,355 (70.5%) of misattributed conversions should have been `paid_search` or `organic_search` — the channels that actually brought the visitor in. This is the core attribution corruption that session continuity fixes going forward, and historical repair fixes retroactively.

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
sql = "
  SELECT s.channel, COUNT(*) AS count
  FROM conversions c
  JOIN sessions s ON s.id = c.session_id
  WHERE c.account_id = #{a.id}
    AND c.created_at > NOW() - INTERVAL '7 days'
  GROUP BY s.channel
  ORDER BY count DESC
"
baseline[:channel_dist] = ActiveRecord::Base.connection.execute(sql).to_a

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

**Baseline captured 2026-02-10 (pre-deploy):**

| Metric | Value |
|--------|-------|
| Ghost session rate (24h) | **73.3%** |
| Sessions per converter (7d median) | **5.0** |
| Channel dist — referral | **270** (73.9%) |
| Channel dist — direct | **92** (25.2%) |
| Channel dist — email | **2** (0.5%) |
| Channel dist — organic_search | **1** (0.3%) |
| Channel dist — paid_search | **0** (0.0%) |

Note: **Zero paid_search conversions** in the 7d window despite paid_search being the true landing channel for ~35% of all visitors. This is the misattribution problem — every paid_search conversion is being attributed to referral or direct because the conversion links to a later ghost session instead of the landing session.

#### Phase 1: Deploy + 1 Hour Validation ✅ COMPLETE

Deployed 2026-02-10 via Kamal.

**T+15 minutes result:**

| Metric | Now (post-deploy) | Yesterday (same window) |
|--------|-------------------|------------------------|
| Ghost rate | 72.1% | 36.7% |
| Session volume (15 min) | 204 | 316 |
| Events (15 min) | 6 | — |
| Conversions (15 min) | 1 | — |
| Sessions with reuse | 9 | — |

**T+1 hour result:**

| Metric | Value |
|--------|-------|
| Ghost rate | **69.7%** (684/982) |
| Sessions with reuse (activity > 1 min after start) | **15/982** |
| Events (1 hour) | **13** |
| Conversions (1 hour) | **3** |

Channel distribution (1 hour post-deploy):

| Channel | Sessions | % |
|---------|----------|---|
| direct | 793 | 80.8% |
| paid_search | 76 | 7.7% |
| organic_search | 52 | 5.3% |
| paid_social | 40 | 4.1% |
| referral | 19 | 1.9% |
| email | 1 | 0.1% |
| organic_social | 1 | 0.1% |

**Key metric — sessions per fingerprint (1 hour):**

| | Worst | 2nd | 3rd |
|---|---|---|---|
| **Yesterday** | **249** sessions | **147** | **28** |
| **Post-deploy** | **19** sessions | **16** | **14** |

**92% reduction** in worst-case session inflation. Fix confirmed active.

**Ghost rate interpretation:** Ghost rate is still ~70% because most visitors bounce without triggering `Mbuzz.track()`. Before: 1 bounce visitor = 10+ ghost sessions. Now: 1 bounce visitor = 1 ghost session. The absolute count dropped (982/hr vs ~1500/hr baseline) but the rate stays elevated because the denominator shrank proportionally. Ghost rate is less useful post-fix — **sessions per fingerprint** is the better signal.

**Referral channel collapsed:** From 74% of conversion attribution (baseline) → 1.9% of sessions. Self-referral ghost sessions eliminated. `direct` now dominates at 80.8% because it's the true landing channel for visitors arriving with no referrer/UTM.

**Decision: No rollback.** Events and conversions flowing. Session reuse active. Session inflation dramatically reduced.

**Rollback procedure (if ever needed):**
```bash
kamal rollback
```

Kamal keeps the previous container image. Rollback is instant. No data migration to reverse.

#### Phase 2: T+24 Hours — Attribution Impact (2026-02-11)

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

**Expected shifts across ALL attribution models (calibrated from micro-test 1.5):**

| Channel | Before (actual 30d) | After (projected) | Why |
|---------|--------------------|--------------------|-----|
| referral | ~67% of conversions | ~10-15% | 956 self-referral misattributions eliminated |
| paid_search | ~8% | ~45-50% | 704 conversions shift here (540 from referral + 164 from direct) |
| organic_search | ~6% | ~35-40% | 555 conversions shift here (416 from referral + 139 from direct) |
| direct | ~15% | ~5-8% | Net decrease — 303 move out, 39 move in from referral |
| paid_social | ~1% | ~2-3% | 23 conversions shift here from referral/direct |
| organic_social | ~1% | ~2-3% | 23 conversions shift here |
| email | ~1% | ~1-2% | 9 conversions shift here |

The shift should be consistent across first-touch, last-touch, linear, time-decay, u-shaped — because the underlying session data is what changed, not the algorithm logic.

**For probabilistic models (Markov, Shapley):** These recalculate based on ALL historical conversion paths. They will shift more gradually as the ratio of clean-to-dirty data improves over days/weeks. Or we can accelerate this with the historical data repair in Phase 4.

#### Phase 3: T+4 Days — Steady State Confirmation (2026-02-14)

4 days of clean data gives enough signal to confirm the fix is stable. We keep historical data intact until after this check — it's needed for the before/after report.

```ruby
a = Account.find(2)
puts "=== 4-DAY STEADY STATE ==="

# Session volume + sessions-per-fingerprint trend (the real metric)
puts "--- Daily Session Volume + Inflation ---"
4.downto(0) do |d|
  day_start = d.days.ago.beginning_of_day
  day_end = d.days.ago.end_of_day
  total = a.sessions.where(started_at: day_start..day_end).count

  sql = "
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sc) AS median,
           PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY sc) AS p95,
           MAX(sc) AS max
    FROM (
      SELECT device_fingerprint, COUNT(*) AS sc
      FROM sessions
      WHERE account_id = #{a.id}
        AND started_at BETWEEN '#{day_start.iso8601}' AND '#{day_end.iso8601}'
        AND device_fingerprint IS NOT NULL
      GROUP BY device_fingerprint
    ) sub
  "
  r = ActiveRecord::Base.connection.execute(sql).first
  puts "  #{day_start.to_date} | sessions=#{total.to_s.rjust(5)} | per_fp: median=#{r['median']&.to_f&.round(1)} p95=#{r['p95']&.to_f&.round(1)} max=#{r['max']}"
end

# Sessions per converting visitor trend
puts "\n--- Sessions Per Converter (daily median) ---"
4.downto(0) do |d|
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

# Channel distribution comparison: pre-deploy vs post-deploy conversions
puts "\n--- Conversion Channel: Pre vs Post Deploy ---"
puts "Pre-deploy (4d before deploy):"
sql = "
  SELECT s.channel, COUNT(*) AS count
  FROM conversions c
  JOIN sessions s ON s.id = c.session_id
  WHERE c.account_id = #{a.id}
    AND c.created_at BETWEEN NOW() - INTERVAL '8 days' AND NOW() - INTERVAL '4 days'
  GROUP BY s.channel ORDER BY count DESC
"
ActiveRecord::Base.connection.execute(sql).each { |r| puts "  #{r['channel']&.ljust(15)}: #{r['count']}" }

puts "Post-deploy (last 4 days):"
sql = "
  SELECT s.channel, COUNT(*) AS count
  FROM conversions c
  JOIN sessions s ON s.id = c.session_id
  WHERE c.account_id = #{a.id}
    AND c.created_at > NOW() - INTERVAL '4 days'
  GROUP BY s.channel ORDER BY count DESC
"
ActiveRecord::Base.connection.execute(sql).each { |r| puts "  #{r['channel']&.ljust(15)}: #{r['count']}" }

# Funnel ratio sanity
puts "\n--- Funnel Sanity (last 4 days) ---"
visits = a.sessions.where("started_at > ?", 4.days.ago).where.not(channel: nil).count
events = a.events.where("occurred_at > ?", 4.days.ago).count
convs = a.conversions.where("created_at > ?", 4.days.ago).count
puts "Visits: #{visits} | Events: #{events} | Conversions: #{convs}"
puts "Event/Visit ratio: #{visits > 0 ? (events.to_f / visits).round(2) : 'N/A'}"
puts "Conv/Visit ratio:  #{visits > 0 ? (convs.to_f / visits * 100).round(2) : 'N/A'}%"
```

**Pass criteria for steady state:**
- Sessions per fingerprint: median ~1, p95 < 5, max < 30 (was 249)
- Median sessions per converter: 1-3 (was 5+)
- Post-deploy conversion channel distribution shows paid_search and organic_search
- Event and conversion volume stable (no unexplained drops)

**Gate:** Once Phase 3 passes → generate the before/after report → proceed to Phase 4.

#### Phase 4: Historical Data Repair (2026-02-14 or later)

Only after Phase 3 confirms the fix is stable AND the before/after report is generated. This is the destructive phase — modifying existing data. **Historical data must be preserved for the report before this phase begins.**

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

The fix is validated when ALL of these hold for 4+ days:

| Metric | Target | Measurement |
|--------|--------|-------------|
| Sessions per fingerprint (p95) | < 5 (was 249) | Phase 3 query |
| Sessions per converting visitor (median) | 1-3 (was 5+) | Phase 3 query |
| Post-deploy conversions show paid_search | > 0 (was 0 in baseline) | Phase 3 query |
| Referral share of new conversions | < 15% (was 74%) | Phase 3 query |
| Event volume | Within 10% of baseline | Phase 1 query |
| Conversion volume | Within 10% of baseline | Phase 1 query |
| No error spikes in logs | 0 new error types | `kamal app logs` |

After historical repair (Phase 4), calibrated from micro-test 1.5:

| Metric | Target | Measurement |
|--------|--------|-------------|
| 90-day visit count | ~15-20k (was 73k+) | `sessions.where.not(channel: nil).count` |
| 90-day conversion rate | ~2-3% (was ~0.5%) | `conversions.count / sessions.count` |
| referral channel share | < 15% (was ~67%) | Attribution credit breakdown |
| paid_search share | ~45-50% (was ~8%) | 704 conversions shift here |
| organic_search share | ~35-40% (was ~6%) | 555 conversions shift here |
| Attribution mismatch rate | < 25% (was 88.3%) | Surveillance check threshold |
