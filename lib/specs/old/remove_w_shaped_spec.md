# Remove W-Shaped Attribution Model

## Summary

Remove the W-shaped attribution model from the codebase. W-shaped attribution requires a "lead creation" touchpoint that doesn't align with our visitor-based tracking model. B2B users who need to track funnel stages (MQL, SQL, Opportunity, Closed Won) should use multiple conversion types instead, making W-shaped redundant.

## Rationale

W-shaped attribution allocates 30% each to:
1. First Touch
2. **Lead Creation** (the problem)
3. Opportunity Creation
4. Last Touch
5. Remaining 10% distributed linearly

The "lead creation" touchpoint requires explicit identification of when a visitor becomes a known lead. This conflicts with our model where:
- Visitors are tracked via `visitor_id`
- Sessions are grouped under visitors
- Conversions are tied to sessions

Without a dedicated "lead creation" event type, W-shaped cannot function correctly.

## Files to Modify

### 1. Core Algorithm
- **DELETE** `app/services/attribution/algorithms/w_shaped.rb`
- **DELETE** `test/services/attribution/algorithms/w_shaped_test.rb`

### 2. Constants & Enums
- `app/constants/attribution_algorithms.rb`
  - Line 12: Remove `:w_shaped` from `ALL` array
  - Line 28: Remove `:w_shaped` from `MULTI_TOUCH` array
  - Line 39: Remove `w_shaped:` from `DESCRIPTIONS` hash

- `app/models/concerns/attribution_model/enums.rb`
  - Line 15: Remove `w_shaped: 5` from enum

- `app/models/concerns/attribution_model/algorithm_mapping.rb`
  - Line 12: Remove `w_shaped: Attribution::Algorithms::WShaped` from `ALGORITHM_CLASSES`

### 3. AML Templates
- `app/services/aml/templates.rb`
  - Lines 58-72: Remove `w_shaped_template` method
  - Remove `:w_shaped` case from `generate` method

### 4. Dashboard Helper
- `app/helpers/dashboard_helper.rb`
  - Line 8: Remove `"w_shaped"` from `ATTRIBUTION_MODEL_OPTIONS` array

### 5. Locales
- `config/locales/en.yml`
  - Line 66: Remove `w_shaped: "W-Shaped"`
  - Line 65: Change `7 attribution models` to `6 attribution models`

### 6. Tests
- `test/services/aml/templates_test.rb`
  - Remove W-shaped template test
  - Line 8: Change `7` to `6` in "generates all algorithm templates" test

- `test/models/attribution_model_test.rb`
  - Line 60: Remove `:w_shaped` from algorithm enum test

### 7. Views (Model Count Updates)
- `app/views/pages/home/_aml_editor.html.erb`
  - Line 6: Change "7 default models" to "6 default models"

- `app/views/pages/home/_pillars.html.erb`
  - Line 43: Change "7 different models" to "6 different models"

### 8. Documentation
- `lib/docs/architecture/attribution_methodology.md`
  - Line 542: Update model count
  - Line 576: Update model count
  - Remove W-shaped sections

- `lib/specs/attribution_editor_spec.md`
  - Lines 6, 20, 104, 299, 430: Update "7" to "6"
  - Remove W-shaped references

## Migration Notes

No database migration needed. The `algorithm` enum in `attribution_models` table stores integers. Removing W-shaped (value 5) from the enum won't affect existing data since no W-shaped models exist in production.

## Verification

After removal:
1. Run full test suite: `rails test`
2. Verify homepage shows "6 default models"
3. Verify AML templates generate for 6 algorithms
4. Verify dashboard filter shows 6 model options
