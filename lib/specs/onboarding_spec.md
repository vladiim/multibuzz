# Onboarding Specification

**Status**: In Progress (Phase 4 Complete)
**Last Updated**: 2025-12-11
**Epic**: E1S4 - Homepage & Onboarding

---

## Executive Summary

This specification defines the complete onboarding flow for new mbuzz customers. The goal is to get users to their **"Aha moment"**—seeing their first conversion attributed across multiple channels—as fast as possible.

**Target Metrics**:
| Metric | Target |
|--------|--------|
| Demo dashboard (no login) | < 30 seconds to value |
| Time to first event | < 5 minutes |
| Time to first attributed conversion | < 24 hours |
| Activation rate | > 40% |
| Onboarding completion rate | > 60% |

---

## 1. SDK Registry

### 1.1 Purpose

A global SDK registry powers the homepage, onboarding wizard, and documentation. Single source of truth for all SDK information.

### 1.2 Data Structure

**Location**: `config/sdk_registry.yml` or `app/models/sdk_registry.rb`

**Fields per SDK**:

| Field | Type | Description |
|-------|------|-------------|
| `key` | Symbol | Unique identifier (`:ruby`, `:python`, etc.) |
| `name` | String | Short name ("Ruby") |
| `display_name` | String | Full name ("Ruby / Rails") |
| `icon` | String | Icon identifier for UI |
| `package_name` | String | Package name ("mbuzz") |
| `package_manager` | String | Where to install ("RubyGems", "PyPI", "npm") |
| `package_url` | String | Link to package registry (nil if not published) |
| `github_url` | String | Link to source repo |
| `docs_url` | String | Link to SDK docs |
| `status` | Symbol | `:live`, `:beta`, or `:coming_soon` |
| `released_at` | Date | When SDK was released (nil if not yet) |
| `install_command` | String | Installation command |
| `init_code` | String | Initialization code snippet |
| `event_code` | String | Event tracking code snippet |
| `conversion_code` | String | Conversion tracking code snippet |
| `identify_code` | String | Identity linking code snippet |
| `category` | Symbol | `:server_side`, `:platform`, or `:api` |
| `sort_order` | Integer | Display order |

### 1.3 SDK List

| SDK | Key | Category | Status | Sort |
|-----|-----|----------|--------|------|
| Ruby / Rails | `:ruby` | server_side | live | 1 |
| Python / Django / Flask | `:python` | server_side | coming_soon | 2 |
| PHP / Laravel | `:php` | server_side | coming_soon | 3 |
| Node.js / Express | `:nodejs` | server_side | coming_soon | 4 |
| Shopify | `:shopify` | platform | coming_soon | 10 |
| Magento / Adobe Commerce | `:magento` | platform | coming_soon | 11 |
| REST API | `:rest_api` | api | live | 99 |

### 1.4 Helper Methods

**Location**: `app/helpers/sdk_helper.rb`

| Method | Returns |
|--------|---------|
| `live_sdks` | SDKs with status `:live` |
| `coming_soon_sdks` | SDKs with status `:coming_soon` |
| `server_side_sdks` | SDKs with category `:server_side` |
| `platform_sdks` | SDKs with category `:platform` |
| `sdk_by_key(key)` | Single SDK by key |
| `sdk_status_badge(status)` | "Live", "Beta", or "Coming Soon" |

### 1.5 Usage Locations

| Location | What to Show |
|----------|--------------|
| Homepage SDK Section | All SDKs with status badges |
| Onboarding Wizard | Server-side SDKs + REST API for selection |
| Documentation Sidebar | All SDKs grouped by category |
| Dashboard Settings | Live SDKs only |
| SDK Waitlist | Coming soon SDKs with email signup |

---

## 2. Public Demo Dashboard (No Login Required)

### 2.1 Purpose

Allow anyone to experience the attribution visualization without signing up. Demonstrates value immediately and reduces friction.

**Route**: `GET /demo`

### 2.2 Demo Data Requirements

| Dimension | Value |
|-----------|-------|
| Time Period | Last 30 days |
| Channels | Paid Search, Organic Search, Paid Social, Email, Direct |
| Sessions | ~500 across channels |
| Conversions | ~50 with revenue $29-$299 |
| Journey Types | Mix of single-touch and multi-touch |

### 2.3 Demo Dashboard Features

1. **Model Switcher**: First Touch, Last Touch, Linear, Time Decay, U-Shaped
2. **Attribution Animation**: Credit flows to channels, animates on model switch
3. **Channel Breakdown**: Bar chart showing credit per channel
4. **Sample Journey**: One detailed customer journey visualization
5. **Prominent CTAs**: "Sign Up Free" and "This is sample data" messaging

### 2.4 UX Flow

```
User lands on /demo
    ↓
Sees pre-populated dashboard with sample data
    ↓
Interacts with model switcher (credit animates)
    ↓
Understands the "aha moment" (same data, different credit allocation)
    ↓
Clicks "Sign Up Free" CTA
    ↓
Redirected to signup (account creation)
```

### 2.5 Files to Create

| File | Purpose |
|------|---------|
| `app/controllers/demo_controller.rb` | Demo dashboard controller |
| `app/views/demo/show.html.erb` | Demo dashboard view |
| `app/services/demo/data_generator_service.rb` | Generate sample data |
| `app/javascript/controllers/demo_attribution_controller.js` | Animation controller |

### 2.6 Implementation Checklist

- [ ] Create `DemoController#show` action
- [ ] Create `Demo::DataGeneratorService` for sample data
- [ ] Build demo dashboard view with model switcher
- [ ] Add interactive attribution animation (Stimulus)
- [ ] Ensure no authentication required
- [ ] Add prominent signup CTAs
- [ ] Track demo engagement (page views, model switches, signup clicks)

---

## 3. Onboarding State Machine

### 3.1 Purpose

Track where each account is in the onboarding flow to show relevant UI, send targeted emails, and measure funnel conversion.

### 3.2 Onboarding Steps

| Step | Key | Trigger | Required? |
|------|-----|---------|-----------|
| 1 | `account_created` | Account created | Yes |
| 2 | `persona_selected` | User picks Developer/Marketer | Yes |
| 3 | `api_key_viewed` | User sees API key | Yes |
| 4 | `sdk_selected` | User picks platform | Yes |
| 5 | `first_event_received` | Any event tracked | Yes |
| 6 | `first_conversion` | Conversion tracked | Yes |
| 7 | `attribution_viewed` | User views attribution | Yes |
| 8 | `identity_linked` | identify() called | No (bonus) |
| 9 | `onboarding_complete` | All required steps done | - |

### 3.3 Activation Milestone

**Definition**: User is "activated" when:
- `first_conversion` step completed AND
- `attribution_viewed` step completed

This is the "aha moment" - seeing their own conversion attributed.

### 3.4 Database Changes

**Table**: `accounts`

| Column | Type | Purpose |
|--------|------|---------|
| `onboarding_progress` | integer | Bitmask of completed steps |
| `onboarding_persona` | integer | 0=developer, 1=marketer, 2=both |
| `selected_sdk` | string | Key of selected SDK |
| `onboarding_started_at` | datetime | When signup completed |
| `onboarding_completed_at` | datetime | When all required steps done |
| `activated_at` | datetime | When activation milestone reached |

### 3.5 Concern Location

**File**: `app/models/concerns/account/onboarding.rb`

**Methods**:
- `onboarding_step_completed?(step)` → Boolean
- `complete_onboarding_step!(step)` → Updates bitmask
- `current_onboarding_step` → Symbol
- `onboarding_percentage` → Integer (0-100)
- `onboarding_complete?` → Boolean
- `activated?` → Boolean

### 3.6 How to Detect Step Completion

| Step | Detection Method |
|------|------------------|
| `account_created` | Automatic on signup |
| `persona_selected` | Form submission |
| `api_key_viewed` | Page view tracking |
| `sdk_selected` | Form submission |
| `first_event_received` | After any event ingested |
| `first_conversion` | After conversion created |
| `attribution_viewed` | Model switcher interaction |
| `identity_linked` | After identify API call |

### 3.7 Implementation Checklist

- [ ] Add onboarding columns to accounts table (migration)
- [ ] Create `Account::Onboarding` concern
- [ ] Add step detection callbacks/jobs
- [ ] Create `Onboarding::StepCompletedJob` for analytics

---

## 4. Onboarding Flow (Step by Step)

### 4.1 Step 1: Signup (Minimal)

**Route**: `GET /signup`, `POST /signup`

**Fields**:
- Email (required)
- Password (required)
- Company name (optional, can be added later)

**On Submit**:
1. Create account
2. Create user with admin role
3. Generate test API key (`sk_test_*`)
4. Set `onboarding_progress = 1` (account_created)
5. Set `onboarding_started_at`
6. Redirect to `/onboarding`

**Design Notes**:
- Single-column centered form
- Link to login for existing users
- No credit card required & generous free plan messaging

**Checklist**:
- [ ] Minimal signup form (email + password only)
- [ ] Auto-generate test API key on account creation
- [ ] Redirect to `/onboarding` after signup

---

### 4.2 Step 2: Persona Selection

**Route**: `GET /onboarding`, `POST /onboarding/persona`

**UI**: Two large clickable cards + text link

```
┌─────────────────────┐    ┌─────────────────────┐
│     👨‍💻             │    │     📊             │
│   Developer         │    │   Marketer          │
│   I'll integrate    │    │   I'll analyze      │
│   the SDK           │    │   the data          │
└─────────────────────┘    └─────────────────────┘

            [Both / I'm not sure]
```

If marketer, give option to invite a developer.

Ensure invited users have similar onboarding flow if the account is not set up.

**On Selection**:
- Store persona in `onboarding_persona`
- Complete `persona_selected` step
- **Developer** → Step 3 (API key + SDK selection)
- **Marketer** → Dashboard tour with demo data overlay
- **Both** → Step 3 (API key + SDK selection)

**Checklist**:
- [ ] Create persona selection UI with large cards
- [ ] Store persona in account
- [ ] Route to appropriate next step

---

### 4.3 Step 3: API Key & SDK Selection

**Route**: `GET /onboarding/setup`

**UI Sections**:

1. **API Key Display**
   - Show full test API key
   - Copy button with feedback
   - Warning: "Store securely, shown once"
   - Link to dashboard to view later

2. **SDK Selection Grid**
   - Grid of SDK cards from SDK_REGISTRY
   - Live SDKs highlighted
   - Coming Soon SDKs grayed with "Join Waitlist" link
   - REST API as fallback option

**On SDK Selection**:
- Store in `selected_sdk`
- Complete `api_key_viewed` and `sdk_selected` steps
- Redirect to Step 4 (installation guide)

If the SDK is not live, show waitlist signup CTA (creates record).

**Checklist**:
- [ ] API key display with copy button
- [ ] SDK grid from SDK_REGISTRY
- [ ] Status badges (Live/Coming Soon)
- [ ] Waitlist signup modal for coming soon SDKs

---

### 4.4 Step 4: SDK Installation Guide

**Route**: `GET /onboarding/install`

**Dynamic content based on `selected_sdk`**:

**Sections**:
1. **Install Package** - Package manager command
2. **Initialize SDK** - Config/initializer code
3. **Add Middleware** (optional) - Framework-specific middleware
4. **Test Installation** - Verification command

**UI Elements**:
- Step numbers (1/4, 2/4, etc.)
- Code blocks with syntax highlighting
- Copy buttons on each code block
- "Next: Verify Installation" CTA

**Checklist**:
- [ ] Dynamic content from SDK_REGISTRY
- [ ] Code blocks with syntax highlighting
- [ ] Copy buttons that track clicks
- [ ] Progress indicator

---

### 4.5 Step 5: Verification (First Event)

**Route**: `GET /onboarding/verify`

**UI States**:

**State A: Waiting**
```
⏳ Waiting for your first event...
   [○ ○ ○ ○ ○] (animated dots)

Run this to test:
┌────────────────────────────────────────┐
│ [verification_command from SDK]        │
└────────────────────────────────────────┘

Having trouble? [Troubleshooting] [Contact Support]
```

**State B: Success**
```
🎉 First Event Received!

Event: test_event
Time: Just now
Status: ✅ Processed

[Track Your First Conversion →]
```

**Technical Implementation**:
- Poll `/onboarding/event_status` every 3 seconds
- Return `{ received: true/false }`
- On success: complete `first_event_received` step
- Show celebration animation
- Auto-advance after 2 seconds

**Checklist**:
- [ ] Polling endpoint for event detection
- [ ] Waiting state with animated indicator
- [ ] Success state with celebration
- [ ] Troubleshooting links
- [ ] Auto-advance to next step

---

### 4.6 Step 6: Conversion Tracking

**Route**: `GET /onboarding/conversion`

**UI**:
```
Track Your First Conversion

Conversions are business outcomes: purchases, signups, etc.

Add this where conversions happen:
┌────────────────────────────────────────┐
│ [conversion_code from SDK]             │
└────────────────────────────────────────┘

Or test with:
┌────────────────────────────────────────┐
│ Mbuzz.conversion('test', revenue: 99)  │
└────────────────────────────────────────┘

⏳ Waiting for conversion...
```

**On conversion received**:
- Complete `first_conversion` step
- Redirect to Step 7 (attribution view)

**Checklist**:
- [ ] Conversion code snippet from SDK_REGISTRY
- [ ] Test conversion command
- [ ] Polling for conversion detection
- [ ] Success state

---

### 4.7 Step 7: Attribution View (Aha Moment!)

**Route**: `GET /onboarding/attribution`

**UI**:
```
🎉 Your First Attribution!

Conversion: test_purchase
Revenue: $99.00

[Interactive attribution visualization]

Try switching models:
[First Touch] [Last Touch] [Linear●] [Time Decay]

──────────────────────────────────────────

✅ You're all set! Your dashboard is ready.

[Go to Dashboard →]
```

**On model switch interaction**:
- Complete `attribution_viewed` step
- Set `activated_at` timestamp
- Mark onboarding complete

**Checklist**:
- [ ] Attribution visualization (same as demo)
- [ ] Interactive model switcher
- [ ] Complete activation milestone on interaction
- [ ] CTA to dashboard

---

### 4.8 Step 8: Identity Linking (Optional/Bonus)

**Location**: In-dashboard prompt, not in main flow

**Trigger**: Show after first 5 conversions OR 7 days

**UI**: Dismissable card in dashboard
```
🔗 Enable Cross-Device Attribution

Link visitors to user IDs to track journeys across devices.

[identify_code from SDK]

[Dismiss] [I've added this]
```

**On "I've added this"** or first identify call:
- Complete `identity_linked` step

**Checklist**:
- [ ] Dashboard prompt card
- [ ] Detect identify API calls
- [ ] Dismissable with "don't show again"

---

## 5. Onboarding Checklist Widget

### 5.1 Purpose

Persistent progress indicator showing current onboarding status. Visible throughout onboarding and early dashboard usage.

### 5.2 Location

- **During onboarding**: Sidebar on right side
- **In dashboard**: Collapsible widget in header or sidebar
- **Dismissable**: After completion or manual dismiss

### 5.3 UI Design

```
┌─────────────────────────────┐
│  Your Setup Progress        │
│                             │
│  ✅ Account created         │
│  ✅ API key viewed          │
│  ✅ SDK selected (Ruby)     │
│  ✅ First event tracked     │
│  ◐  First conversion    ←   │
│  ○  Attribution viewed      │
│  ○  Identity linked         │
│                             │
│  Progress: 57%              │
│  █████████░░░░░░░           │
│                             │
│  [Continue Setup]           │
│  [Skip & explore]           │
└─────────────────────────────┘
```

**States**:
- ✅ Completed (green checkmark)
- ◐ In progress (half-filled, highlighted)
- ○ Not started (empty circle)

### 5.4 Behavior

| Action | Result |
|--------|--------|
| Click completed step | Link to relevant docs |
| Click in-progress step | Resume onboarding flow |
| Click "Continue Setup" | Go to current step |
| Click "Skip & explore" | Go to dashboard, keep widget visible |
| Complete all steps | Show celebration, auto-dismiss after 5 sec |
| Click X to dismiss | Hide widget, set preference |

### 5.5 Files

| File | Purpose |
|------|---------|
| `app/views/shared/_onboarding_checklist.html.erb` | Checklist partial |
| `app/javascript/controllers/onboarding_checklist_controller.js` | Interactivity |

### 5.6 Checklist

- [ ] Create checklist partial
- [ ] Progress bar calculation
- [ ] Step click navigation
- [ ] Dismissal with preference storage
- [ ] Celebration animation on completion

---

## 6. Email Onboarding Sequence

### 6.1 Email Schedule

| # | Email | Trigger | Timing |
|---|-------|---------|--------|
| 1 | Welcome | Signup | Immediate |
| 2 | Setup Nudge | No events | Day 1 (24h after signup) |
| 3 | Feature Highlight | First event OR Day 3 | Day 3 |
| 4 | Success Story | Activated OR Day 7 | Day 7 |
| 5 | Trial Reminder | 7 days before end | Day 7-14 |
| 6 | Final Reminder | 1 day before end | Day 13-20 |

### 6.2 Email Details

#### Email 1: Welcome (Immediate)

**Subject**: Welcome to mbuzz – your API key is ready

**Content**:
- Greeting with first name
- Test API key (partially redacted, link to dashboard)
- Quick start steps (numbered list)
- CTA: "Start Setup"
- Reply-to for questions

---

#### Email 2: Setup Nudge (Day 1, conditional)

**Subject**: Need help getting started?

**Condition**: `first_event_received` NOT completed

**Content**:
- Acknowledge they haven't tracked yet
- Common blockers with solutions
- Offer setup call (Calendly link)
- Personal sign-off from founder

---

#### Email 3: Feature Highlight (Day 3)

**Subject**: See attribution in action

**Condition**: After first event OR Day 3 (whichever is later)

**Content**:
- Explain attribution models
- Screenshot/GIF of model comparison
- CTA: "View Your Attribution"

---

#### Email 4: Success Story (Day 7)

**Subject**: How [Company] reduced CAC by 32%

**Content**:
- Brief case study
- Specific results with numbers
- CTA: "See Your Data"

---

#### Email 5 & 6: Trial Reminders

**Subject**: Your trial ends in [X] days

**Content**:
- Summary of data collected
- What happens when trial ends
- Upgrade CTA
- Data export option

### 6.3 Files

| File | Purpose |
|------|---------|
| `app/mailers/onboarding_mailer.rb` | Mailer class |
| `app/views/onboarding_mailer/` | Email templates |
| `app/jobs/onboarding/email_sequence_job.rb` | Scheduling job |

### 6.4 Checklist

- [ ] Create OnboardingMailer with all templates
- [ ] Schedule emails via Solid Queue
- [ ] Conditional logic based on onboarding state
- [ ] Track opens/clicks
- [ ] Unsubscribe handling

---

## 7. Empty States

### 7.1 Purpose

When users land on pages with no data, guide them toward the action needed.

### 7.2 Empty State Pattern

Each empty state includes:
1. **Icon** - Visual indicator
2. **Headline** - What this page shows
3. **Explanation** - Why it's empty
4. **Code snippet** - How to populate it
5. **Actions** - Copy code, view demo, read docs

### 7.3 Empty States to Create

| Page | Headline | Primary Action |
|------|----------|----------------|
| Dashboard | No attribution data yet | Track first conversion |
| Conversions | No conversions tracked | Add conversion code |
| Events | Waiting for events | Run test event |
| Sessions | No sessions yet | Install SDK |
| Visitors | No visitors tracked | Install SDK |

### 7.4 Files

**Location**: `app/views/shared/empty_states/`

| File | Used On |
|------|---------|
| `_dashboard.html.erb` | Dashboard |
| `_conversions.html.erb` | Conversions index |
| `_events.html.erb` | Events index |
| `_sessions.html.erb` | Sessions index |

### 7.5 Checklist

- [ ] Create empty state partials
- [ ] Include code snippets from SDK_REGISTRY
- [ ] "View Demo Data" links to /demo
- [ ] Consistent design across all states

---

## 8. Metrics & Tracking

### 8.1 Onboarding Events to Track

| Event | Properties |
|-------|------------|
| `onboarding_step_completed` | `step`, `time_since_signup` |
| `sdk_selected` | `sdk` |
| `code_copied` | `snippet`, `sdk` |
| `demo_viewed` | `duration`, `models_switched` |
| `email_opened` | `email_type` |
| `email_clicked` | `email_type`, `cta` |

### 8.2 Funnel Definition

```
Signup
  ↓ (target: 95%)
Persona Selected
  ↓ (target: 90%)
SDK Selected
  ↓ (target: 70%)
First Event
  ↓ (target: 60%)
First Conversion
  ↓ (target: 80%)
Attribution Viewed (ACTIVATED)
```

### 8.3 Time-Based Alerts

| Transition | Target | Alert Threshold |
|------------|--------|-----------------|
| Signup → First Event | < 5 min | > 24 hours |
| First Event → Conversion | < 24 hours | > 7 days |
| Conversion → Attribution | < 1 min | > 1 hour |

### 8.4 Dashboard Metrics

Create internal dashboard showing:
- Daily signups
- Funnel conversion rates
- Median time per step
- Drop-off points
- Email performance

### 8.5 Checklist

- [ ] Implement onboarding event tracking (dogfood mbuzz)
- [ ] Create internal onboarding dashboard
- [ ] Set up Slack alerts for drop-offs
- [ ] Weekly funnel review process

---

## 9. Implementation Plan

### Phase 1: Foundation

- [ ] Add onboarding columns migration
- [ ] Create `Account::Onboarding` concern
- [ ] Create SDK_REGISTRY data structure
- [ ] Create `SdkHelper` module

### Phase 2: Public Demo

- [ ] Create DemoController
- [ ] Create Demo::DataGeneratorService
- [ ] Build demo dashboard view
- [ ] Add attribution animation
- [ ] Test without authentication

### Phase 3: Onboarding Flow

- [ ] OnboardingController with all steps
- [ ] Persona selection UI
- [ ] API key display with copy
- [ ] SDK selection grid
- [ ] SDK-specific installation guides
- [ ] Real-time event verification
- [ ] Conversion tracking step
- [ ] Attribution visualization

### Phase 4: Supporting Features

- [ ] Onboarding checklist widget
- [ ] Empty state partials
- [ ] OnboardingMailer with templates
- [ ] Email scheduling jobs

### Phase 5: Analytics

- [ ] Onboarding event tracking
- [ ] Internal funnel dashboard
- [ ] Alerts setup

---

## 10. Success Criteria

### Launch Checklist

- [ ] Demo dashboard works without login
- [ ] Full onboarding flow tested end-to-end
- [ ] All emails sending correctly
- [ ] Empty states implemented
- [ ] Mobile responsive
- [ ] Analytics tracking working

### 30-Day Success Metrics

| Metric | Target |
|--------|--------|
| Activation rate | > 40% |
| Time to first event (median) | < 10 minutes |
| Onboarding completion | > 60% |
| Email open rate | > 40% |
| Setup support tickets | < 10% of signups |

---

## 11. Test/Live Mode Dashboard

### 11.1 Purpose

Like Stripe, users need to see their test data during onboarding before they're ready to go live. The dashboard should clearly distinguish between test and production environments.

### 11.2 Key Insight

**Infrastructure already exists but is NOT connected:**
- All models have `is_test` boolean column (events, conversions, sessions, visitors, attribution_credits)
- Scopes exist: `scope :production, -> { where(is_test: false) }` and `scope :test_data, -> { where(is_test: true) }`
- `Dashboard::BaseController` has `view_mode`, `test_mode?`, `environment_scope` methods
- **Problem**: `test_mode?` is NOT passed to `ConversionsDataService` or scope builders

### 11.3 Test/Live Mode Toggle

**Location**: Dashboard navbar (near account dropdown)

**UI Design**:
```
┌─────────────────────────────────────────────────────────────┐
│ mbuzz    [Conversions] [Funnel] [Events]    [🔘 Test Mode ▼] │
└─────────────────────────────────────────────────────────────┘
```

**Toggle States**:
| State | Visual | Badge Color | Data Shown |
|-------|--------|-------------|------------|
| Test Mode | "Test Mode" badge | Yellow/Amber | `is_test: true` |
| Live Mode | "Live" badge (or nothing) | Gray/Green | `is_test: false` |

**Implementation**:
- Form POST to `/dashboard/view_mode` with `mode` param
- Store in `session[:view_mode]` ("test" or "production")
- Reload dashboard with filtered data

### 11.4 Test Mode Banner

When in test mode, show prominent banner:

```
┌─────────────────────────────────────────────────────────────┐
│ ⚠️ You're viewing test data. Use sk_test_* keys for testing. │
│                                    [Switch to Live Mode →]  │
└─────────────────────────────────────────────────────────────┘
```

**Styling**: Yellow/amber background, dismissable but reappears on page load

### 11.5 Default Mode Logic

| Account State | Default Mode |
|---------------|--------------|
| `!onboarding_complete?` | Test |
| `onboarding_complete? && !has_live_data?` | Test |
| `has_live_data?` | Production |

### 11.6 Implementation Checklist

- [ ] Pass `test_mode: test_mode?` from `BaseController.filter_params` to services
- [ ] Update `ConversionsDataService` to pass `test_mode` to scope builders
- [ ] Update cache keys to include `test_mode`
- [ ] Add Test/Live toggle button to navbar
- [ ] Add test mode banner partial
- [ ] Default to test mode for incomplete onboarding
- [ ] Add "Switch to Live Mode" in empty production state

---

## 12. Post-Onboarding "Go Live" Flow

### 12.1 Purpose

After users complete SDK setup with test data, guide them to deploy to production. This is the critical transition from "trying" to "using" the product.

### 12.2 Go Live Checklist

Show in dashboard for accounts where `test_mode_has_data? && !live_mode_has_data?`:

```
┌─────────────────────────────────────────────────────────────┐
│  Ready to Go Live?                                    [X]   │
│                                                             │
│  ✅ SDK installed (Ruby)                                    │
│  ✅ First event tracked                                     │
│  ✅ First conversion tracked                                │
│  ⬜ Generate live API key                                   │
│  ⬜ Deploy to production                                    │
│                                                             │
│  [Generate Live API Key]  [View Go-Live Guide]              │
└─────────────────────────────────────────────────────────────┘
```

### 12.3 Go Live Steps

#### Step 1: Generate Live API Key

**Trigger**: Click "Generate Live API Key" button

**UI**: Modal or inline expansion showing:
```
Your Live API Key (save this - shown once):

  sk_live_abc123def456...                    [Copy]

Replace sk_test_* with sk_live_* in your production environment.
```

**Action**: Creates API key with `environment: :live`

#### Step 2: Environment Variable Guide

```
Production Deployment Checklist:

1. Set environment variable:
   MBUZZ_API_KEY=sk_live_your_key_here

2. Verify middleware is active in production:
   # config/environments/production.rb
   config.middleware.use Mbuzz::Middleware::Tracking

3. Deploy and verify events are coming through
```

#### Step 3: First Live Event Detection

After live API key is generated, show:
```
⏳ Waiting for first live event...

Once you deploy, you'll see live data here.
You're currently viewing: [Test Data ▼]
```

When first live event received:
```
🎉 Live data is flowing!

Your production environment is now tracking events.
[Switch to Live Mode →]
```

### 12.4 API Key Management

**Location**: Account Settings → API Keys

**UI Design**:
```
┌─────────────────────────────────────────────────────────────┐
│  API Keys                                                   │
│                                                             │
│  Test Keys                                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ sk_test_••••••••••••7a3f   Created Dec 10  [Revoke] │   │
│  └─────────────────────────────────────────────────────┘   │
│  [+ Generate Test Key]                                      │
│                                                             │
│  Live Keys                                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ No live keys yet                                     │   │
│  │ Generate a live key when you're ready for production │   │
│  └─────────────────────────────────────────────────────┘   │
│  [+ Generate Live Key]                                      │
└─────────────────────────────────────────────────────────────┘
```

### 12.5 Empty State: No Live Data

When user switches to Live Mode but has no live data:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│              📊 No live data yet                            │
│                                                             │
│  You're viewing production data, but no events have been    │
│  tracked with a live API key yet.                           │
│                                                             │
│  [Generate Live Key]  [View Test Data]  [Go-Live Guide]     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 12.6 Onboarding Completion States

| State | Banner/UI | CTA |
|-------|-----------|-----|
| No events (test or live) | Onboarding checklist | Continue Setup |
| Test events only | Go Live checklist | Generate Live Key |
| Live events, no conversions | Conversion prompt | Add conversion tracking |
| Live conversions | None (fully activated) | - |

### 12.7 Implementation Checklist

- [ ] Add `has_test_data?` and `has_live_data?` methods to Account
- [ ] Create Go Live checklist partial
- [ ] Add "Generate Live Key" button/flow
- [ ] Create empty state for no live data
- [ ] Detect first live event and show celebration
- [ ] Update API Keys page with test/live sections
- [ ] Add Go-Live documentation page

---

## 13. Updated Implementation Plan

### Phase 1: Foundation (DONE)
- [x] Onboarding columns migration
- [x] `Account::Onboarding` concern
- [x] SDK_REGISTRY data structure
- [x] SignupController with test API key generation

### Phase 2: Onboarding Flow (DONE)
- [x] OnboardingController with all steps
- [x] Persona selection
- [x] API key display with copy
- [x] SDK selection grid
- [x] SDK-specific installation guides
- [x] Real-time event verification (Hotwire)
- [x] Conversion tracking step
- [x] Step completion guards (redirect if already done)

### Phase 3: Test/Live Mode (DONE)
- [x] Connect `test_mode?` to dashboard data queries
- [x] Add Test/Live toggle in navbar (Stripe-style)
- [x] Add test mode banner
- [x] Default to test mode for incomplete onboarding
- [x] Update cache keys to include test_mode

### Phase 4: Go Live Flow (DONE)
- [x] Setup guidance banners (API key → events → conversions → users)
- [x] "Generate Live Key" flow with show-once modal
- [x] Setup modals with SDK code examples
- [x] Fixed clipboard controller for API key copy
- [x] Docs URLs use Rails route helpers

### Phase 5: Supporting Features
- [ ] Onboarding checklist widget (dashboard sidebar)
- [ ] Empty state partials
- [ ] OnboardingMailer with templates
- [ ] Email scheduling jobs

### Phase 6: Analytics
- [ ] Onboarding event tracking (dogfood)
- [ ] Internal funnel dashboard
- [ ] Alerts setup

---

## Related Documents

- [SDK Specification](../docs/sdk/sdk_specification.md)
- [Streamlined SDK Spec](../docs/sdk/streamlined_sdk_spec.md)
- [Homepage Visualization Spec](./homepage_visualization_spec.md)
- [API Contract](../docs/sdk/api_contract.md)
