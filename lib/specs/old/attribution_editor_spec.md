# Attribution Model Editor - Implementation Spec

**Status**: ✅ Complete
**Created**: 2025-12-08
**Completed**: 2025-12-09

---

## Overview

This spec covers the UI for managing attribution models, including:
- Viewing and editing the 6 default templates
- Creating custom models (paid plans)
- AML validation with server-side checking
- Testing models with sample journeys

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Attribution Models                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  AML::Templates │  │ AttributionModel│  │  AML::Executor  │  │
│  │  (6 defaults)   │──│  (user models)  │──│  (validation)   │  │
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
│  │ (list all)  │    │ (textarea)  │    │ (custom)    │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Plan Limits

| Plan    | Edit Defaults    | Custom Models | Total Models |
|---------|------------------|---------------|--------------|
| Free    | Variables only   | 0             | 6            |
| Starter | Full AML         | 3             | 10           |
| Growth  | Full AML         | 5             | 12           |
| Pro     | Full AML         | 10            | 17           |

---

## Attribution Reruns ✅

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

### Data Model Changes ✅

#### attribution_models - columns added
- [x] `version` (integer, default: 1)
- [x] `version_updated_at` (datetime)

#### attribution_credits - column added
- [x] `model_version` (integer)

#### rerun_jobs table created
- [x] Migration and model created

### Rerun Services ✅
- [x] `Attribution::RerunService` - processes conversions in batches
- [x] `Attribution::RerunInitiationService` - handles billing/limits
- [x] `AttributionRerunProcessingJob` - background worker

---

## Implementation Checklist

### Phase 1: Templates Service ✅

- [x] Create `AML::Templates` module
  - [x] Define DEFINITIONS hash with 6 templates
  - [x] Each template has: key, name, description, code (with %{lookback_days} interpolation)
  - [x] `generate(algorithm, lookback_days:)` method
  - [x] `all` method returning list of templates
  - [x] `find(algorithm)` method
- [x] Write tests for Templates
  - [x] Test each template generates valid AML
  - [x] Test lookback_days interpolation
  - [x] Test generated code passes security validation
  - [x] Test generated code executes successfully

### Phase 2: Plan Limits ✅

- [x] Add `CUSTOM_MODEL_LIMITS` to `Billing` constants
- [x] Add `Account#custom_model_limit` method
- [x] Add `Account#custom_models_count` method
- [x] Add `Account#can_create_custom_model?` method
- [x] Add `Account#can_edit_full_aml?` method (paid plans only)
- [x] Write tests for limit methods

### Phase 3: Controller ✅

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
- [x] Implement `rerun` action
  - [x] Attribution rerun workflow

### Phase 4: Controller Tests ✅

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

### Phase 5: Index View ✅

- [x] List 6 default templates
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

### Phase 6: Edit View ✅

- [x] Model name input (editable for custom, read-only for defaults)
- [x] Lookback days input
- [x] Code editor section
  - [x] Free plan: Read-only code preview + variable inputs
  - [x] Paid plans: Full textarea editor
- [x] Server-side validation on form submit
- [x] Save button
- [x] Cancel button (back to index)
- [x] Reset to Default button (for edited defaults)
- [x] Delete button (for custom models only)

### Phase 7: CodeMirror Integration (DEFERRED)

Using simple textarea with server-side validation. CodeMirror can be added later for enhanced editing experience.

- [ ] Add CodeMirror 6 via importmap or npm
- [ ] Create Stimulus controller `code_editor_controller.js`
- [ ] Style CodeMirror to match app theme

### Phase 8: Test Panel ✅

- [x] Expandable "Test Your Model" section
- [x] Sample journey presets:
  - [x] 4 touchpoints (organic → email → paid → direct)
  - [x] 2 touchpoints (paid social → email)
  - [x] Single touchpoint (organic search)
- [x] "Run Test" button
- [x] Results display (via Turbo Frame):
  - [x] Visual bar chart of credit distribution
  - [x] Touchpoint → credit mapping
  - [x] Total validation (shows green/red based on sum)

### Phase 9: Stimulus Controllers ✅

- [x] `code_editor_controller.js` - Basic functionality
- [x] Test panel uses Turbo Frames (no custom JS needed)

### Phase 10: Attribution Reruns ✅

- [x] Version tracking (version, version_updated_at columns added)
- [x] model_version tracking in attribution_credits
- [x] Stale credit detection
- [x] RerunJob model created
- [x] Attribution::RerunService implemented
- [x] Attribution::RerunInitiationService for billing
- [x] Background job (AttributionRerunProcessingJob)
- [x] Rerun confirmation view
- [x] Tests for rerun services

---

## Test Coverage Summary

- **Controller tests**: 726+ lines
- **Service tests**: Covered in attribution models and AML tests
- **All CRUD operations tested**
- **Plan limit enforcement tested**
- **Authorization and scoping tested**

---

## Deferred Items (Future Enhancement)

These items are explicitly deferred for future releases:

1. **CodeMirror Integration** - Enhanced code editing experience
2. **Real-time validation display** - Currently uses server-side validation on submit
3. **UI indicators for stale count** - Warning badges on index page
4. **Rerun modal with plan usage visualization**
5. **Progress tracking via Turbo Streams for reruns**

---

## Security Considerations ✅

1. **Account scoping** - All queries scoped to current_account
2. **AML validation** - Always validate before save/execute
3. **Plan enforcement** - Check limits server-side, not just UI
4. **CSRF protection** - All POST/PATCH/DELETE require token
