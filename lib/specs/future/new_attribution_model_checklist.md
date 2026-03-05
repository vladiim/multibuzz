# New Attribution Model Checklist

When adding a new attribution model, update all locations below.

---

## 1. Core Implementation

| File | What to Update | Required |
|------|----------------|----------|
| `app/models/concerns/attribution_model/enums.rb` | Add to `algorithm` enum with next integer | Yes |
| `app/models/concerns/attribution_model/algorithm_mapping.rb` | Add class mapping to `ALGORITHM_CLASSES` | Yes |
| `app/services/attribution/algorithms/{model}.rb` | Create algorithm class with `call` method | Yes |
| `app/services/attribution/calculator.rb` | Handle special initialization if needed (e.g., Markov needs conversion_paths) | If different |

---

## 2. Constants & Helpers

| File | What to Update | Required |
|------|----------------|----------|
| `app/constants/attribution_algorithms.rb` | Add constant, add to `ALL`, `IMPLEMENTED` arrays | Heuristic only |
| `app/helpers/dashboard_helper.rb` | Add to `ATTRIBUTION_MODEL_DESCRIPTIONS` hash | Yes |

---

## 3. Default Models for New Accounts

| File | What to Update | Required |
|------|----------------|----------|
| `app/constants/attribution_algorithms.rb` | Add to `DEFAULTS` if auto-created for new accounts | Optional |
| `app/models/concerns/account/callbacks.rb` | Uses `DEFAULTS` - no change needed | N/A |

---

## 4. AML Templates (Heuristic Models Only)

| File | What to Update | Required |
|------|----------------|----------|
| `app/services/aml/templates.rb` | Add AML template to `DEFINITIONS` | Heuristic only |

---

## 5. Tests

| File | What to Update | Required |
|------|----------------|----------|
| `test/services/attribution/algorithms/{model}_test.rb` | Create comprehensive unit tests | Yes |
| `test/services/attribution/calculator_test.rb` | Add integration tests if special handling | If different |
| `test/fixtures/attribution_models.yml` | Add fixture for testing | Optional |

---

## 6. UI Updates

| File | What to Update | Required |
|------|----------------|----------|
| `app/views/accounts/attribution_models/index.html.erb` | Uses AML templates - auto-updates for heuristic | N/A |

---

## 7. Homepage & Marketing

| File | What to Update | Required |
|------|----------------|----------|
| `config/locales/en.yml` | Update "7 Attribution Models" count in features | Yes |
| `app/views/pages/home/_aml_editor.html.erb` | Add tab for new model (heuristic only) | Optional |
| `app/javascript/controllers/aml_showcase_controller.js` | Add model definition to MODELS object | Optional |

---

## 8. Documentation

| File | What to Update | Required |
|------|----------------|----------|
| `app/views/docs/_attribution_models.html.erb` | Add example if AML-based | Heuristic only |
| `lib/docs/architecture/attribution_methodology.md` | Document algorithm behavior | Recommended |
| `lib/specs/data_driven_attribution_models_spec.md` | Update spec with implementation status | Recommended |

---

## Model Type Differences

### Heuristic Models (Tier 1)
- Rule-based, no training data needed
- Have AML templates
- Added to homepage showcase
- Auto-created for new accounts

### Probabilistic Models (Tier 2)
- Data-driven but no ML training
- No AML templates (native Ruby)
- May need special Calculator handling
- Require data thresholds (500+ conversions)

### ML Models (Tier 3)
- Require Python sidecar for training
- Need training status fields
- Require significant data (2000+ conversions)

---

## Status Tracker

### Heuristic (Tier 1) - All Complete
- [x] First Touch
- [x] Last Touch
- [x] Linear
- [x] Time Decay
- [x] U-Shaped
- [x] Participation

### Probabilistic (Tier 2)
- [x] Markov Chain - Complete (all checklist items done)
- [x] Shapley Value - Complete (all checklist items done)
- [ ] Ordered Shapley - Pending

### ML (Tier 3)
- [ ] Logistic Regression
- [ ] Gradient Boosting
- [ ] Neural Network (LSTM)

---

## Quick Checklist Template

```
## [Model Name] Implementation

### Core
- [ ] `enums.rb` - Add enum value
- [ ] `algorithm_mapping.rb` - Add class mapping
- [ ] `algorithms/{model}.rb` - Create algorithm
- [ ] `calculator.rb` - Special handling (if needed)

### Helpers
- [ ] `attribution_algorithms.rb` - Add constant (heuristic only)
- [ ] `dashboard_helper.rb` - Add description

### Tests
- [ ] `algorithms/{model}_test.rb` - Unit tests
- [ ] `calculator_test.rb` - Integration tests (if needed)

### Marketing
- [ ] `en.yml` - Update model count
- [ ] `_aml_editor.html.erb` - Add tab (optional)
- [ ] `aml_showcase_controller.js` - Add definition (optional)

### Docs
- [ ] `_attribution_models.html.erb` - Add example (if AML)
- [ ] `attribution_methodology.md` - Document algorithm
```
