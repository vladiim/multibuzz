# Spec: Public Demo Dashboard

## Overview

Expand the existing `/demo` route into a full public dashboard experience that mirrors the authenticated dashboard. This allows prospects to explore the product without creating an account, supporting self-service sales and reducing friction in the buyer journey.

**Goal:** Let visitors experience the complete dashboard with realistic sample data before signing up.

**Why this matters:**
- 88% of B2B buyers won't book a sales call without seeing the product first
- 72% expect self-serve, digital-first evaluation experience
- Gated demos create friction that reduces conversions

---

## Current State vs. Target State

| Aspect | Current | Target |
|--------|---------|--------|
| Public demo URL | `/demo` (attribution teaser only) | `/demo/dashboard` (full dashboard) |
| Tabs available | None (single view) | Conversions, Funnel, Events placeholder |
| CLV mode | Not available | Full CLV dashboard with dummy data |
| Filters | Not available | Visual only (decorative, shows capability) |
| Model switcher | Yes (attribution models) | Yes (same functionality) |
| Authentication | None required | None required |
| CTA placement | Header + bottom banner | Persistent header + contextual CTAs |

---

## URL Structure

```
/demo                           → Landing/teaser (keep as lightweight entry point)
/demo/dashboard                 → Full demo dashboard (default: conversions tab)
/demo/dashboard/conversions     → Conversions tab (Turbo Frame target)
/demo/dashboard/funnel          → Funnel tab (Turbo Frame target)
/demo/dashboard/clv             → CLV mode toggle endpoint
/demo/dashboard/attribution     → Attribution model switcher (Turbo Frame target)
```

**Decision:** Keep `/demo` as a lightweight teaser that links to "Explore Full Dashboard" (`/demo/dashboard`). This provides two entry points:
1. Quick teaser for homepage links
2. Full experience for serious evaluators

---

## Architecture

### Design Pattern: Parallel Controller Hierarchy

Mirror the authenticated dashboard structure under a `Demo::` namespace. This provides clean separation while enabling maximum view reuse.

```
Authenticated                          Public Demo
─────────────────────────────────────────────────────────────
Dashboard::BaseController              Demo::DashboardController
  └─ requires authentication             └─ no authentication
  └─ scoped to current_account           └─ uses dummy services
  └─ real data services                  └─ session-based state

Dashboard::ConversionsController       Demo::Dashboard::ConversionsController
Dashboard::FunnelController            Demo::Dashboard::FunnelController
Dashboard::ClvModeController           Demo::Dashboard::ClvModeController
```

### Design Pattern: Service Substitution

Controllers call the same service interface but substitute dummy implementations:

| Context | Service Called |
|---------|----------------|
| Authenticated | `Dashboard::ConversionsDataService.new(current_account, filter_params)` |
| Demo | `Dashboard::Dummy::ConversionsDataService.call` |

The dummy services already exist and return identical data structures, making view reuse seamless.

### Design Pattern: View Composition with Partials

Demo views compose existing dashboard partials within a demo-specific shell:

```
Demo Shell (demo-specific)
├── Demo Nav (demo-specific)
├── Demo Badge Banner (demo-specific)
├── Tab Container (shared toggle controller)
│   ├── Conversions Content (reuse dashboard/_full_dashboard.html.erb)
│   ├── Funnel Content (reuse dashboard/funnel partials)
│   └── Events Placeholder (demo-specific)
└── CTA Banner (demo-specific)
```

### State Management

| State | Authenticated | Demo |
|-------|---------------|------|
| CLV mode | `session[:clv_mode]` | `session[:demo_clv_mode]` |
| View mode (test/prod) | `session[:view_mode]` | Not applicable |
| Filters | Query params + account data | Not applicable |
| Attribution model | Query params | Query params |

Demo uses separate session keys to avoid conflicts if a logged-in user visits the demo.

---

## Features

### Core Dashboard Features

| Feature | Demo Behavior | Implementation |
|---------|---------------|----------------|
| **Conversions Tab** | Full functionality with dummy data | Reuse existing partials |
| **Funnel Tab** | Full functionality with dummy data | Reuse existing partials |
| **Events Tab** | Placeholder with "Live only" message | Demo-specific placeholder |
| **CLV Mode Toggle** | Works, switches between transaction/CLV views | Session-based toggle |
| **Attribution Model Switcher** | Works, updates channel credit distribution | Query param based |
| **KPI Cards** | Display dummy metrics | Reuse existing partials |
| **Channel Table** | Display dummy channel breakdown | Reuse existing partials |
| **Time Series Chart** | Display dummy trend data | Reuse existing partials |
| **Smiling Curve (CLV)** | Display dummy lifecycle data | Reuse existing partials |
| **Cohort Table (CLV)** | Display dummy cohort data | Reuse existing partials |

### Disabled/Decorative Features

| Feature | Demo Behavior | Rationale |
|---------|---------------|-----------|
| **Filters** | Visible but disabled with "Sign up to filter" tooltip | Would require complex dummy data variations |
| **Export** | Hidden or disabled | No meaningful data to export |
| **Test/Production Toggle** | Hidden | Only relevant with real data |
| **Model Comparison Mode** | Hidden | Keep demo simple |
| **Real-time Events** | Placeholder | Requires WebSocket + real data |

### Demo-Specific Features

| Feature | Purpose |
|---------|---------|
| **Demo Badge Banner** | Persistent yellow banner indicating sample data |
| **Simplified Nav** | Logo + "Demo Dashboard" badge + Sign Up CTA |
| **Contextual CTAs** | "Sign up to..." prompts on disabled features |
| **Bottom CTA Banner** | Prominent signup call-to-action after content |
| **Events Placeholder** | Explains live events feature with signup prompt |

---

## UX Design Principles

### 1. Persistent Demo Context
- Yellow "Demo Dashboard" badge in navigation
- "Sample Data" banner at top of content area
- Visual distinction from authenticated dashboard (subtle background color shift)

### 2. Progressive Value Revelation
- Default to Conversions tab (most impressive metrics)
- CLV mode available but not default (advanced feature discovery)
- Funnel as secondary exploration path

### 3. Friction-Free Conversion Path
- Signup CTA always visible in header
- Contextual CTAs on disabled features ("Sign up to filter your data")
- Bottom CTA after scrolling through content
- Single-click path to signup from any point

### 4. Feature Education
- Disabled features hint at full capabilities
- Events placeholder explains real-time functionality
- Tooltips on hover for key metrics

---

## Component Inventory

### Demo-Specific Components (New)

| Component | Purpose |
|-----------|---------|
| `demo/dashboard/show.html.erb` | Main shell/layout for demo dashboard |
| `demo/dashboard/_nav.html.erb` | Simplified nav with demo badge and signup CTA |
| `demo/dashboard/_demo_badge.html.erb` | Yellow "Sample Data" banner with signup prompt |
| `demo/dashboard/_cta_banner.html.erb` | Bottom signup CTA section |
| `demo/dashboard/_events_placeholder.html.erb` | Placeholder for disabled events tab |
| `demo/dashboard/_clv_toggle.html.erb` | CLV mode switcher (demo version) |
| `demo/dashboard/_disabled_filters.html.erb` | Decorative filters button with tooltip |
| `demo/dashboard/conversions/show.html.erb` | Turbo Frame wrapper for conversions |
| `demo/dashboard/funnel/show.html.erb` | Turbo Frame wrapper for funnel |

### Reusable Components (Existing)

| Component | Reusable As-Is? | Notes |
|-----------|-----------------|-------|
| `dashboard/conversions/_full_dashboard.html.erb` | Yes | Renders from `@result` |
| `dashboard/conversions/_clv_dashboard.html.erb` | Yes | Renders from `@clv_data` |
| `dashboard/conversions/_kpi_cards.html.erb` | Yes | Pure presentation |
| `dashboard/conversions/_channel_table.html.erb` | Yes | Pure presentation |
| `dashboard/conversions/_time_series_chart.html.erb` | Yes | Pure presentation |
| `dashboard/conversions/_skeleton.html.erb` | Yes | Loading state |
| `dashboard/funnel/_funnel_chart.html.erb` | Yes | Pure presentation |
| `dashboard/funnel/_stage_breakdown.html.erb` | Yes | Pure presentation |
| `dashboard/funnel/_skeleton.html.erb` | Yes | Loading state |

---

## Data Services

### Existing Dummy Services (No Changes Needed)

| Service | Returns |
|---------|---------|
| `Dashboard::Dummy::ConversionsDataService` | Totals, channel breakdown, time series, campaigns |
| `Dashboard::Dummy::FunnelDataService` | Funnel stages, conversion rates, channel breakdown |
| `Dashboard::Dummy::ClvDataService` | CLV metrics, smiling curve, cohort analysis |

These services return hardcoded realistic data matching the structure of real services.

---

## Analytics & Tracking

Track demo engagement to measure conversion funnel effectiveness:

| Event | Properties | Purpose |
|-------|------------|---------|
| `demo_dashboard_viewed` | `tab`, `referrer` | Track entry and tab engagement |
| `demo_tab_switched` | `from_tab`, `to_tab` | Measure exploration depth |
| `demo_clv_mode_toggled` | `mode` | Track advanced feature interest |
| `demo_model_switched` | `model` | Track attribution model interest |
| `demo_signup_clicked` | `location` | Measure CTA effectiveness |
| `demo_disabled_feature_clicked` | `feature` | Identify high-interest gated features |

---

## SEO Considerations

The demo dashboard should be indexable:

| Page | Title | Description |
|------|-------|-------------|
| `/demo/dashboard` | "Interactive Demo - mbuzz Attribution Analytics" | "Explore our attribution dashboard with sample data. See how mbuzz tracks customer journeys across channels." |

Ensure `robots.txt` allows:
```
Allow: /demo/
Allow: /demo/dashboard
```

---

## Security Considerations

| Concern | Mitigation |
|---------|------------|
| Auth bypass risk | Demo routes completely separate from authenticated routes |
| Data exposure | Only hardcoded dummy data served, no database queries |
| Session conflicts | Demo uses separate session keys (`demo_clv_mode` vs `clv_mode`) |
| Abuse/scraping | Consider rate limiting if demo generates significant load |

---

## Success Metrics

| Metric | Target | Calculation |
|--------|--------|-------------|
| Demo → Signup rate | >5% | `demo_signup_clicked` / `demo_dashboard_viewed` |
| Avg time on demo | >60s | Analytics session duration on demo pages |
| Tab exploration rate | >30% | Visitors who view 2+ tabs |
| CLV mode exploration | >10% | Visitors who toggle to CLV mode |
| Funnel tab views | >20% | Visitors who click Funnel tab |

---

## Implementation Checklist

### Phase 1: Routes & Controllers

- [ ] Add `namespace :demo` routes to `config/routes.rb`
- [ ] Create `Demo::DashboardController` (main shell)
- [ ] Create `Demo::Dashboard::ConversionsController` (conversions tab)
- [ ] Create `Demo::Dashboard::FunnelController` (funnel tab)
- [ ] Create `Demo::Dashboard::ClvModeController` (CLV toggle)
- [ ] Add controller tests for all demo endpoints
- [ ] Verify no authentication required on any demo route

### Phase 2: Demo Shell Views

- [ ] Create `app/views/demo/dashboard/show.html.erb` (main layout)
- [ ] Create `app/views/demo/dashboard/_nav.html.erb` (simplified nav)
- [ ] Create `app/views/demo/dashboard/_demo_badge.html.erb` (sample data banner)
- [ ] Create `app/views/demo/dashboard/_cta_banner.html.erb` (bottom CTA)
- [ ] Create `app/views/demo/dashboard/_disabled_filters.html.erb` (decorative filters)
- [ ] Create `app/views/demo/dashboard/_events_placeholder.html.erb` (events tab placeholder)
- [ ] Create `app/views/demo/dashboard/_clv_toggle.html.erb` (mode switcher)

### Phase 3: Tab Content Views

- [ ] Create `app/views/demo/dashboard/conversions/show.html.erb` (Turbo Frame wrapper)
- [ ] Create `app/views/demo/dashboard/funnel/show.html.erb` (Turbo Frame wrapper)
- [ ] Verify existing dashboard partials render correctly with dummy data
- [ ] Test Turbo Frame lazy loading works correctly
- [ ] Test CLV mode toggle updates view correctly

### Phase 4: Integration & Polish

- [ ] Add "Explore Full Dashboard" link to existing `/demo` page
- [ ] Verify all signup CTAs link correctly
- [ ] Test session isolation (demo state doesn't affect authenticated users)
- [ ] Test attribution model switching works
- [ ] Verify mobile responsiveness
- [ ] Add loading skeletons for Turbo Frame content

### Phase 5: Analytics & SEO

- [ ] Add analytics tracking events for demo engagement
- [ ] Add meta tags for SEO (title, description, og:tags)
- [ ] Verify demo pages are crawlable (check robots.txt)
- [ ] Set up conversion tracking for demo → signup funnel

### Phase 6: Launch & Promotion

- [ ] Add demo dashboard link to homepage hero section
- [ ] Add demo dashboard link to pricing page
- [ ] Add demo dashboard link to navigation (public pages)
- [ ] Update any "Book a Demo" CTAs to include self-serve option
- [ ] Create internal dashboard to monitor demo analytics

---

## File Structure

### New Files

```
app/controllers/demo/
├── dashboard_controller.rb
└── dashboard/
    ├── conversions_controller.rb
    ├── funnel_controller.rb
    └── clv_mode_controller.rb

app/views/demo/dashboard/
├── show.html.erb
├── _nav.html.erb
├── _demo_badge.html.erb
├── _cta_banner.html.erb
├── _clv_toggle.html.erb
├── _disabled_filters.html.erb
├── _events_placeholder.html.erb
├── conversions/
│   └── show.html.erb
└── funnel/
    └── show.html.erb

test/controllers/demo/
├── dashboard_controller_test.rb
└── dashboard/
    ├── conversions_controller_test.rb
    ├── funnel_controller_test.rb
    └── clv_mode_controller_test.rb
```

### Modified Files

```
config/routes.rb                    # Add demo dashboard namespace
app/views/demo/show.html.erb        # Add "Explore Full Dashboard" link
app/views/pages/home.html.erb       # Add demo CTA (optional)
app/views/layouts/_nav.html.erb     # Add demo link to public nav (optional)
```

---

## Future Enhancements

| Enhancement | Description | Priority |
|-------------|-------------|----------|
| **Personalized Demo** | Capture industry/use-case to show relevant sample data | Medium |
| **Interactive Filters** | Pre-computed data variations for simulated filtering | Low |
| **Guided Tour** | Tooltips walkthrough explaining each section | Medium |
| **Temporary Demo Accounts** | Full account with seeded data, expires after 7 days | Low |
| **Demo Customization** | Let prospects input their channels to see sample attribution | High |
| **Video Overlay** | Optional video explanation of each section | Low |

---

## References

- [Reprise - SaaS Demo Guide](https://www.reprise.com/resources/blog/saas-demo-complete-guide)
- [HowdyGo - SaaS Product Demo](https://www.howdygo.com/blog/saas-product-demo)
- [DemoDazzle - SaaS Demo Conversions](https://demodazzle.com/blog/how-to-create-saas-product-demos-that-skyrocket-conversions)
