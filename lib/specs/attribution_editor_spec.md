# Attribution Model Editor - Implementation Spec

## Overview

This spec covers the UI for managing attribution models, including:
- Viewing and editing the 7 default templates
- Creating custom models (paid plans)
- Real-time AML validation with CodeMirror editor
- Testing models with sample journeys

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Attribution Models                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  AML::Templates │  │ AttributionModel│  │  AML::Executor  │  │
│  │  (7 defaults)   │──│  (user models)  │──│  (validation)   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│           │                    │                    │            │
│           ▼                    ▼                    ▼            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              AttributionModelsController                     ││
│  │  index | show | edit | update | create | destroy | validate ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│           ┌──────────────────┼──────────────────┐               │
│           ▼                  ▼                  ▼               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   Index     │    │    Edit     │    │    New      │         │
│  │ (list all)  │    │ (CodeMirror)│    │ (custom)    │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Plan Limits

| Plan    | Edit Defaults    | Custom Models | Total Models |
|---------|------------------|---------------|--------------|
| Free    | Variables only   | 0             | 7            |
| Starter | Full AML         | 3             | 10           |
| Growth  | Full AML         | 5             | 12           |
| Pro     | Full AML         | 10            | 17           |

---

## Attribution Reruns

### The Problem

When a user edits an attribution model, existing conversions have attribution credits calculated with the **old** model logic. This creates inconsistency:

- New conversions use the updated model
- Historical conversions use the outdated model
- Reports mix old and new attribution logic

Users need the ability to **rerun** attribution on historical conversions to apply the updated model.

### Model Versioning

Track model changes with a version number:

```
┌─────────────────────────────────────────────────────────────────┐
│ Attribution Model                                                │
├─────────────────────────────────────────────────────────────────┤
│ id: 123                                                          │
│ name: "First Touch"                                              │
│ version: 3              ← increments on each edit               │
│ version_updated_at: 2024-12-08 10:30:00                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Attribution Credits                                              │
├─────────────────────────────────────────────────────────────────┤
│ conversion_id: 456                                               │
│ attribution_model_id: 123                                        │
│ model_version: 2        ← version when credit was calculated    │
│ is_stale: true          ← derived: version < model.version      │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight**: Credits where `model_version < model.current_version` are "stale" and need rerunning.

### Plan Limits for Reruns

Rerun limits match the event quota per plan:

| Plan    | Included Reruns/Month | Overage Rate (per 10K) |
|---------|----------------------|------------------------|
| Free    | 10,000               | N/A (capped by event limit) |
| Starter | 50,000               | $0.83                  |
| Growth  | 250,000              | $0.57                  |
| Pro     | 1,000,000            | $0.43                  |

**Notes**:
- Rerun limits match event limits per plan
- Free plans can't exceed their rerun limit (max 10K events = max 10K conversions)
- Limits reset monthly with billing period
- Overage = `event_overage / 7` (reattributing one of seven models)

- Starter: $5.80/10K events → $0.83/10K reruns
- Growth: $3.96/10K events → $0.57/10K reruns
- Pro: $2.99/10K events → $0.43/10K reruns

### Metered Billing for Reruns

Reuse existing metered billing infrastructure - bill in 10K blocks based on stale conversion count:

```
┌─────────────────────────────────────────────────────────────────┐
│ Rerun Calculation                                                │
├─────────────────────────────────────────────────────────────────┤
│ Stale conversions: 23,450                                        │
│ Blocks required: ceil(23,450 / 10,000) = 3 blocks               │
│                                                                  │
│ Plan included remaining: 37,500                                  │
│ → Covered by plan (no charge)                                    │
│                                                                  │
│ OR if over limit:                                                │
│ Plan included remaining: 5,000                                   │
│ Overage: 23,450 - 5,000 = 18,450 → 2 blocks                     │
│ Charge: 2 × $0.83 = $1.66                                        │
└─────────────────────────────────────────────────────────────────┘
```

Usage order:
1. Deduct from included plan reruns (reset monthly with billing period)
2. Bill overage blocks to Stripe meter (same as event overages)

### UI Design

#### Index View - Stale Badge

Show when conversions have outdated attribution:

```
┌─────────────────────────────────────────────────────────────────┐
│ First Touch                                    [Edit] [Default] │
│ 100% credit to first touchpoint                                 │
│                                                                  │
│ ⚠️ 2,450 stale conversions                    [Rerun Attribution]│
└─────────────────────────────────────────────────────────────────┘
```

- Orange warning icon with count
- "Rerun Attribution" button opens modal
- Tooltip: "Attribution was calculated with an older version of this model"

#### Rerun Modal

```
┌─────────────────────────────────────────────────────────────────┐
│ Rerun Attribution                                          [X]  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ Model: First Touch (v3)                                          │
│ Stale conversions: 23,450                                        │
│ Date range: Nov 1 - Dec 7, 2024                                  │
│                                                                  │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Plan Reruns: 37,500 / 50,000 remaining this period         │ │
│ │ ████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 75%    │ │
│ │                                                              │ │
│ │ This rerun uses 23,450 → Covered by plan ✓                  │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ OR if over limit:                                                │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Plan Reruns: 5,000 / 50,000 remaining this period          │ │
│ │                                                              │ │
│ │ This rerun: 23,450                                          │ │
│ │ From plan:  -5,000                                          │ │
│ │ Overage:    18,450 → 2 blocks × $0.83 = $1.66               │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ○ Rerun all 23,450 stale conversions                            │
│ ○ Rerun last 30 days only (8,500)                               │
│ ○ Rerun last 7 days only (1,200)                                │
│                                                                  │
│                              [Cancel]  [Rerun Attribution]       │
└─────────────────────────────────────────────────────────────────┘
```

### Background Processing

Reruns processed asynchronously with progress tracking:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ User clicks  │────▶│ Create Rerun │────▶│ Background   │
│ "Rerun"      │     │ Job Record   │     │ Worker       │
└──────────────┘     └──────────────┘     └──────────────┘
                            │                    │
                            ▼                    ▼
                     ┌──────────────┐     ┌──────────────┐
                     │ Status:      │     │ Process in   │
                     │ pending →    │◀────│ batches of   │
                     │ processing → │     │ 1000         │
                     │ completed    │     └──────────────┘
                     └──────────────┘
```

UI shows: "Rerunning: 1,250 / 2,450 (51%)"

### Data Model Changes

#### attribution_models - add columns

```ruby
t.integer :version, default: 1, null: false
t.datetime :version_updated_at
```

#### attribution_credits - add column

```ruby
t.integer :model_version, null: false
```

#### accounts - add column

```ruby
t.integer :reruns_used_this_period, default: 0, null: false
```

Resets with `current_period_start` (same as event usage).

#### New: rerun_jobs

```ruby
create_table :rerun_jobs do |t|
  t.references :account, null: false
  t.references :attribution_model, null: false
  t.integer :status, default: 0  # pending/processing/completed/failed
  t.integer :total_conversions, null: false
  t.integer :processed_conversions, default: 0
  t.integer :from_version
  t.integer :to_version
  t.integer :overage_blocks, default: 0  # blocks billed to Stripe
  t.datetime :started_at
  t.datetime :completed_at
  t.timestamps
end
```

### Billing Constants

```ruby
# app/constants/billing.rb

RERUN_LIMITS = {
  PLAN_FREE => 10_000,
  PLAN_STARTER => 50_000,
  PLAN_GROWTH => 250_000,
  PLAN_PRO => 1_000_000
}.freeze

# Overage = event_overage / 7 (rounded)
RERUN_OVERAGE_CENTS = {
  PLAN_STARTER => 83,   # $5.80 / 7
  PLAN_GROWTH => 57,    # $3.96 / 7
  PLAN_PRO => 43        # $2.99 / 7
}.freeze
```

### Implementation Phases

#### Phase 1: Versioning
- [ ] Add `version` to attribution_models
- [ ] Add `model_version` to attribution_credits
- [ ] Increment version on model update
- [ ] Store version when creating credits

#### Phase 2: UI Indicators
- [ ] Show stale count on index page
- [ ] Add warning badge
- [ ] "Rerun Attribution" button

#### Phase 3: Rerun Billing
- [ ] Add `reruns_used_this_period` to accounts
- [ ] Add RERUN_LIMITS to Billing constants
- [ ] Add RERUN_OVERAGE_CENTS to Billing constants
- [ ] Account#rerun_limit, #reruns_remaining methods

#### Phase 4: Rerun Execution
- [ ] Create rerun_jobs table
- [ ] Build Attribution::RerunService
- [ ] Background job with batch processing
- [ ] Progress tracking via Turbo Streams
- [ ] Bill overage blocks to Stripe meter

---

## 7 Default Templates

1. **First Touch** - 100% to first touchpoint
2. **Last Touch** - 100% to last touchpoint
3. **Linear** - Equal credit to all touchpoints
4. **Time Decay** - Exponential decay toward conversion
5. **U-Shaped** - 40% first, 40% last, 20% middle
6. **W-Shaped** - 30% first, 30% lead creation, 30% last, 10% rest
7. **Participation** - 100% to each touchpoint (non-normalized)

## Data Model

### AttributionModel (existing)

```ruby
# Already exists with:
# - account_id (FK)
# - name (string)
# - model_type (enum: preset/custom)
# - algorithm (enum: first_touch, last_touch, etc.)
# - dsl_code (text) - stores customized code
# - lookback_days (integer, 1-365)
# - is_active (boolean)
# - is_default (boolean)
```

### New: Plan limits in billing.rb

```ruby
CUSTOM_MODEL_LIMITS = {
  free: 0,
  starter: 3,
  growth: 5,
  pro: 10
}.freeze
```

## Routes

```ruby
namespace :account do
  resources :attribution_models, except: [:show] do
    member do
      post :validate    # Real-time AML validation
      post :test        # Test with sample journey
      post :reset       # Reset to default template
      post :set_default # Set as account default
    end
  end
end
```

## Implementation Checklist

### Phase 1: Templates Service

- [x] Create `AML::Templates` module
  - [x] Define DEFINITIONS hash with 7 templates
  - [x] Each template has: key, name, description, code (with %{lookback_days} interpolation)
  - [x] `generate(algorithm, lookback_days:)` method
  - [x] `all` method returning list of templates
  - [x] `find(algorithm)` method
- [x] Write tests for Templates
  - [x] Test each template generates valid AML
  - [x] Test lookback_days interpolation
  - [x] Test generated code passes security validation
  - [x] Test generated code executes successfully

### Phase 2: Plan Limits

- [x] Add `CUSTOM_MODEL_LIMITS` to `Billing` constants
- [x] Add `Account#custom_model_limit` method
- [x] Add `Account#custom_models_count` method
- [x] Add `Account#can_create_custom_model?` method
- [x] Add `Account#can_edit_full_aml?` method (paid plans only)
- [x] Write tests for limit methods

### Phase 3: Controller

- [x] Create `Account::AttributionModelsController`
- [x] Implement `index` action
  - [x] Load default templates from AML::Templates
  - [x] Load custom models from database
  - [x] Include limit info for UI
- [x] Implement `edit` action
  - [x] For defaults: generate code from template
  - [x] For custom: load dsl_code
  - [x] Check permissions (free = variables only)
- [x] Implement `update` action
  - [x] Validate AML code before save
  - [x] Save dsl_code for customized defaults
  - [x] Handle validation errors
- [x] Implement `create` action
  - [x] Check custom model limit
  - [x] Validate AML code
  - [x] Create new model
- [x] Implement `destroy` action
  - [x] Prevent deleting default models
  - [x] Only allow deleting custom models
- [x] Implement `validate` action (JSON endpoint)
  - [x] Parse and validate AML code
  - [x] Return errors with line/column/suggestion
  - [x] Return success with parsed structure
- [x] Implement `test` action
  - [x] Execute AML with sample touchpoints
  - [x] Return credit distribution (via Turbo Frame)
- [x] Implement `reset` action
  - [x] Clear dsl_code, restore template
- [x] Implement `set_default` action
  - [x] Set is_default flag
  - [x] Clear other defaults

### Phase 4: Controller Tests

- [x] Test index loads defaults and custom models
- [x] Test edit returns template code for defaults
- [x] Test update saves customized code
- [x] Test update validates AML before save
- [x] Test create respects plan limits
- [x] Test create validates AML
- [x] Test destroy prevents deleting defaults
- [x] Test destroy allows deleting custom models
- [x] Test validate endpoint returns errors
- [x] Test validate endpoint returns success
- [x] Test test endpoint executes AML
- [x] Test reset clears customization
- [x] Test set_default updates flags
- [x] Test authorization (account scoping)

### Phase 5: Index View

- [x] List 7 default templates
  - [x] Show name, description
  - [x] Show "Customized" badge if dsl_code present
  - [x] Edit button
  - [x] Reset button (if customized)
- [x] List custom models (if any)
  - [x] Show name
  - [x] Edit/Delete buttons
- [x] "Create Custom Model" button
  - [x] Show limit: "2 of 3 custom models"
  - [x] Disable if at limit
  - [x] Upgrade prompt if free plan
- [x] Default model indicator (star icon)
- [x] Set Default action on each model

### Phase 6: Edit View

- [x] Model name input (editable for custom, read-only for defaults)
- [x] Lookback days input
- [x] Code editor section
  - [x] Free plan: Read-only code preview + variable inputs
  - [x] Paid plans: Full textarea editor (CodeMirror deferred)
- [x] Server-side validation on form submit
- [x] Save button
- [x] Cancel button (back to index)
- [x] Reset to Default button (for edited defaults)
- [x] Delete button (for custom models only)

### Phase 7: CodeMirror Integration (DEFERRED)

Using simple textarea with server-side validation for now. CodeMirror can be added later for enhanced editing experience.

- [ ] Add CodeMirror 6 via importmap or npm
- [ ] Create Stimulus controller `code_editor_controller.js`
- [ ] Style CodeMirror to match app theme

### Phase 8: Test Panel

- [x] Expandable "Test Your Model" section
- [x] Sample journey presets:
  - [x] 4 touchpoints (organic → email → paid → direct)
  - [x] 2 touchpoints (paid social → email)
  - [x] Single touchpoint (organic search)
  - [ ] Custom (editable JSON) - deferred
- [x] "Run Test" button
- [x] Results display (via Turbo Frame):
  - [x] Visual bar chart of credit distribution
  - [x] Touchpoint → credit mapping
  - [x] Total validation (shows green/red based on sum)

### Phase 9: Stimulus Controllers

- [x] `code_editor_controller.js` - Basic syntax highlighting
- [ ] `validation_controller.js` - Real-time validation display (deferred)
- [x] Test panel uses Turbo Frames (no custom JS needed)
- [ ] `model_form_controller.js` - Form state management (deferred)

### Phase 10: Polish

- [ ] Loading states during validation/test
- [ ] Keyboard shortcuts (Cmd+S to save)
- [ ] Unsaved changes warning
- [ ] Mobile responsive layout
- [ ] Error toast notifications
- [ ] Success feedback on save

## API Endpoints

### GET /account/attribution_models
Returns index page with all models.

### GET /account/attribution_models/:id/edit
Returns edit form for model.

### PATCH /account/attribution_models/:id
Updates model. Params:
```json
{
  "attribution_model": {
    "name": "My Custom Model",
    "lookback_days": 30,
    "dsl_code": "within_window 30.days do..."
  }
}
```

### POST /account/attribution_models
Creates custom model. Same params as update.

### DELETE /account/attribution_models/:id
Deletes custom model (not defaults).

### POST /account/attribution_models/:id/validate
Validates AML code without saving.
```json
// Request
{ "dsl_code": "within_window 30.days do..." }

// Success Response
{ "valid": true }

// Error Response
{
  "valid": false,
  "errors": [
    {
      "message": "Forbidden method: system",
      "line": 4,
      "column": 2,
      "suggestion": "Remove system calls"
    }
  ]
}
```

### POST /account/attribution_models/:id/test
Tests AML with sample journey.
```json
// Request
{
  "dsl_code": "within_window 30.days do...",
  "journey": "default" // or "two_touch" or "single" or custom array
}

// Response
{
  "success": true,
  "results": [
    { "touchpoint": 1, "channel": "organic", "credit": 0.4 },
    { "touchpoint": 2, "channel": "email", "credit": 0.1 },
    { "touchpoint": 3, "channel": "paid", "credit": 0.1 },
    { "touchpoint": 4, "channel": "direct", "credit": 0.4 }
  ],
  "total": 1.0
}
```

### POST /account/attribution_models/:id/reset
Resets default model to template.

### POST /account/attribution_models/:id/set_default
Sets model as account default.

## Security Considerations

1. **Account scoping** - All queries scoped to current_account
2. **AML validation** - Always validate before save/execute
3. **Plan enforcement** - Check limits server-side, not just UI
4. **CSRF protection** - All POST/PATCH/DELETE require token
5. **Rate limiting** - Consider rate limiting validate/test endpoints

## Dependencies

- **CodeMirror 6** - Code editor (~150KB)
- **AML::Executor** - Already implemented
- **AML::Security::ASTAnalyzer** - Already implemented

## Open Questions

1. **W-Shaped template** - Needs "lead creation" stage. How to identify?
   - Option: Use middle touchpoint as proxy
   - Option: Wait for user-defined stages feature

2. **Participation model** - Credits don't sum to 1.0 (100% each).
   - Need to handle this specially in validation?

## File Structure

```
app/
├── controllers/
│   └── account/
│       └── attribution_models_controller.rb
├── javascript/
│   └── controllers/
│       ├── code_editor_controller.js
│       ├── validation_controller.js
│       └── test_panel_controller.js
├── services/
│   └── aml/
│       └── templates.rb
└── views/
    └── account/
        └── attribution_models/
            ├── index.html.erb
            ├── edit.html.erb
            ├── new.html.erb
            └── _form.html.erb
```
