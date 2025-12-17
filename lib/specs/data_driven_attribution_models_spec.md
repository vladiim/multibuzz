# Data-Driven Attribution Models - Specification

## 1. Model Classification

### Tier 1: Heuristic (Implemented ✅)
First Touch, Last Touch, Linear, Time Decay, U-Shaped, Participation

### Tier 2: Probabilistic (No Training Required)
| Model | Algorithm | Min Data | Status |
|-------|-----------|----------|--------|
| Markov Chain | Removal effect calculation | 500 conversions, 5+ channels | ✅ Implemented |
| Shapley Value | Marginal contribution averaging | 500 conversions, 5-15 channels | ✅ Implemented |
| Ordered Shapley | Position-weighted Shapley | 1,000 conversions | Pending |
| Bayesian Network | Augmented naive Bayes | 500 conversions, 5+ channels | Pending |

### Tier 3: Machine Learning (Training Required)
| Model | Algorithm | Min Data |
|-------|-----------|----------|
| Logistic Regression | Bagged ensemble averaging | 2,000 conversions, 20k journeys |
| Additive Hazard | Survival analysis with time factors | 2,000 conversions, 4 months |
| Gradient Boosting | XGBoost/LightGBM | 3,000 conversions |
| Hidden Markov Model | Latent state funnel modeling | 3,000 conversions |
| Neural Network (LSTM) | Sequential deep learning | 5,000 conversions, 50k journeys |

### Tier 4: Lead Scoring & Prediction
| Model | Output | Min Data |
|-------|--------|----------|
| Conversion Probability | 0-100 score per journey | 3,000 conversions, 50k journeys |
| Next Best Channel | Recommended channel to maximize conversion | Same as parent model |

---

## 2. Data Requirements

### 2.1 Minimum Thresholds (Conservative)

| Model | Conversions | Journeys | Channels | Time Range |
|-------|------------|----------|----------|------------|
| Markov Chain | 500+ | 2,000+ | 5+ | 2 months |
| Shapley Value | 500+ | 2,000+ | 5-15 | 2 months |
| Bayesian Network | 500+ | 2,000+ | 5+ | 2 months |
| Logistic Regression | 2,000+ | 20,000+ | Any | 3 months |
| Additive Hazard | 2,000+ | 20,000+ | Any | 4 months |
| Gradient Boosting | 3,000+ | 30,000+ | Any | 4 months |
| Hidden Markov Model | 3,000+ | 30,000+ | Any | 4 months |
| Neural Network | 5,000+ | 50,000+ | Any | 6 months |
| Lead Scoring | 3,000+ | 50,000+ | Any | 6 months |

### 2.2 Imbalanced Data Handling

Attribution data typically has **1-5% conversion rates**, making datasets highly imbalanced. Without proper handling, models achieve high accuracy by predicting the majority class (non-conversion) while having near-zero sensitivity for conversions.

**Required Preprocessing:**

| Technique | Description | Use Case |
|-----------|-------------|----------|
| **SMOTE** | Synthetic Minority Over-sampling Technique - generates synthetic minority samples | Tier 3 ML models |
| **ROS** | Random Over-Sampling - duplicates minority class samples | Quick baseline, Tier 2 validation |
| **RUS** | Random Under-Sampling - reduces majority class | Large datasets, fast iteration |
| Class Weights | Adjust loss function to penalize minority misclassification | Neural networks, Gradient Boosting |

**Implementation:**
```python
# Example: SMOTE for training data
from imblearn.over_sampling import SMOTE
smote = SMOTE(random_state=42)
X_train_balanced, y_train_balanced = smote.fit_resample(X_train, y_train)
```

**Recommendation:** Apply SMOTE for Tier 3 models when conversion rate < 5%.

### 2.3 Validation Metrics

**Do NOT use accuracy as primary metric** - it's misleading for imbalanced attribution data.

| Metric | Formula | When to Use |
|--------|---------|-------------|
| **Geometric Mean (GM)** | √(TPR × TNR) | **Primary metric** - balances sensitivity and specificity |
| TPR (Sensitivity/Recall) | TP / (TP + FN) | Measures conversion prediction accuracy |
| TNR (Specificity) | TN / (TN + FP) | Measures non-conversion prediction accuracy |
| AUC-ROC | Area under ROC curve | Overall model discrimination ability |
| Precision | TP / (TP + FP) | When false positives are costly |
| F1 Score | 2 × (Precision × Recall) / (Precision + Recall) | Balance precision and recall |

**Minimum Thresholds for Production:**
- GM ≥ 0.55 for Tier 2 models
- GM ≥ 0.60 for Tier 3 models
- AUC-ROC ≥ 0.70 for ML models

### 2.4 Feature Engineering

**Core Features (Required):**
- Channel sequence (channel₁, channel₂, ..., channelₙ)
- Journey outcome (conversion/non-conversion)
- Conversion value (if applicable)

**Enhanced Features (Recommended):**
| Feature | Description | Impact |
|---------|-------------|--------|
| Inter-touchpoint timing | Time period between consecutive touchpoints | +5-10% accuracy |
| Previous conversions | Count of visitor's prior conversions (loyalty indicator) | +3-5% accuracy |
| Journey length | Number of touchpoints in path | Useful for segmentation |
| Device type | Mobile/desktop/tablet per touchpoint | Cross-device attribution |
| Day of week / Hour | Temporal patterns | Time-based optimization |

---

## 3. Model Specifications

### 3.1 Markov Chain

**Algorithm:** 1st-order transition matrix with removal effect

**How it works:**
1. Build transition probability matrix from channel sequences
2. Add "Start" and absorbing states ("Conversion", "Non-conversion")
3. Calculate baseline conversion probability P(conversion)
4. For each channel, calculate removal effect:
   ```
   RE(channel) = 1 - P(conversion | channel removed) / P(conversion)
   ```
5. Normalize removal effects to get attribution percentages:
   ```
   Attribution(channel) = RE(channel) / Σ RE(all channels)
   ```

**Configuration Options:**
| Option | Default | Description |
|--------|---------|-------------|
| `order` | 1 | Markov chain order (1-4). Higher = more context, more data needed |
| `include_timing` | false | Include discretized time periods between touchpoints |
| `null_state_handling` | "proportional" | How to handle missing transitions |

**Higher-Order Markov:**
- 2nd order: P(channelₙ | channelₙ₋₁, channelₙ₋₂) - requires 2x more data
- 3rd/4th order: Rarely needed, requires 4-8x more data
- Use when journey patterns show strong sequential dependencies

**References:**
- Anderl et al. (2016) - "Mapping the customer journey"

### 3.2 Shapley Value

**Algorithm:** Game-theoretic marginal contribution averaging

**How it works:**
1. Treat channels as "players" in a cooperative game
2. For each possible coalition (subset of channels):
   - Calculate conversion probability with coalition
   - Calculate marginal contribution of each channel joining
3. Average marginal contributions across all orderings
4. Result: Fair attribution based on each channel's incremental value

**Complexity:** O(2ⁿ) where n = number of channels
- Practical limit: 15 channels (32,768 coalitions)
- For >15 channels: Use sampling-based approximation

**Configuration:**
| Option | Default | Description |
|--------|---------|-------------|
| `max_channels` | 15 | Limit channels (group rare ones into "Other") |
| `sampling` | false | Use Monte Carlo sampling for large channel sets |
| `sample_size` | 10000 | Number of samples if sampling enabled |

### 3.3 Ordered Shapley

**Algorithm:** Position-weighted Shapley value

Extends standard Shapley by considering **position** in the journey, not just presence. A channel appearing first vs last may have different attribution.

**Additional Data Requirement:** 1,000+ conversions (needs position-specific samples)

### 3.4 Bayesian Network

**Algorithm:** Augmented naive Bayes with negative observation propagation for removal effect

**Structure:**
```
                    outcome
                   /   |   \
                  /    |    \
           channel₁→channel₂→...→channelₙ
              ↓        ↓           ↓
           period₁  period₂    (optional)
                                   ↑
                               previous
```

**Advantages over Markov Chain:**
- Explicitly encodes position (channel₁, channel₂, etc.)
- Can incorporate time periods between touchpoints
- Supports "previous conversion count" as loyalty indicator
- Real-time conversion probability during journey
- Predicts next best channel to recommend

**Attribution via Negative Observation Propagation:**
Instead of removing channels from data (expensive), propagate evidence that channel ≠ value:
```
P(conversion | channel_k ≠ X for all k) vs P(conversion)
```

**Configuration:**
| Option | Default | Description |
|--------|---------|-------------|
| `max_journey_length` | 13 | Maximum touchpoints to model |
| `include_periods` | false | Add time period variables |
| `include_previous` | false | Add previous conversion count |
| `period_bins` | [1h, 1d, 7d, 30d] | Discretization for time periods |

**Implementation:** Use pgmpy (Python) or equivalent Bayesian network library.

**References:**
- Ben Mrad & Hnich (2024) - "Intelligent attribution modeling for enhanced digital marketing performance"

### 3.5 Hidden Markov Model

**Algorithm:** Latent state modeling through conversion funnel

Models customer's **hidden mental state** (awareness, consideration, intent) as they progress through touchpoints. Channels influence state transitions.

**Use Case:** When you believe customers progress through funnel stages not directly observable from channel data.

**References:**
- Abhishek et al. (2012) - "Media exposure through the funnel"

### 3.6 Neural Network Models

Neural networks offer the highest accuracy potential for attribution but require more data and compute. We support three architectures in order of complexity:

#### 3.6.1 LSTM with Attention (DNAMTA-style)

**Algorithm:** Long Short-Term Memory with attention mechanism and time-decay

Based on the DNAMTA framework (Li et al., 2018), this model captures:
- Long-range dependencies via LSTM memory cells
- Touchpoint contextual importance via attention
- Time-decay effects via survival functions

**Architecture:**
```
                    ┌─────────────┐
Touchpoints ──────► │  Embedding  │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
Time Periods ─────► │    LSTM     │ ◄──── User Features (optional)
                    │   Layers    │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  Attention  │ ──► Attention Weights (attribution)
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   Dense     │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  Sigmoid    │ ──► Conversion Probability
                    └─────────────┘
```

**LSTM Cell Components:**
- **Forget gate**: Controls what information to discard from previous states
- **Input gate**: Determines which new information to store
- **Cell state**: Maintains long-term dependencies across the journey
- **Output gate**: Selects what information to pass forward

**Attention Mechanism:**
The same touchpoint may be differentially important at different positions/frequencies. Attention lets the model weight individual touchpoints when constructing path representations:
```python
attention_weights = softmax(W @ hidden_states)
context = sum(attention_weights * hidden_states)
```

**Time-Decay Integration:**
Survival time-decay functions model the diminishing effect of older touchpoints:
```python
decay_factor = exp(-lambda * time_since_touchpoint)
```

**Configuration:**
| Option | Default | Description |
|--------|---------|-------------|
| `embedding_dim` | 32 | Channel embedding dimension |
| `lstm_units` | 64 | LSTM hidden layer size |
| `lstm_layers` | 2 | Number of stacked LSTM layers |
| `dropout` | 0.2 | Regularization dropout rate |
| `attention` | true | Enable attention mechanism |
| `time_decay` | true | Enable survival time-decay |
| `bidirectional` | false | Use bidirectional LSTM |

**Data Requirements:**
- Minimum: 5,000 conversions, 50,000 journeys
- Recommended: 10,000+ conversions for stable attention weights
- Monthly updates require ~1,000 new conversions

#### 3.6.2 Transformer with Self-Attention

**Algorithm:** Multi-head self-attention (similar to BERT/GPT architecture)

Based on recent research (Lu & Kannan, 2025), transformers can:
- Process all touchpoints simultaneously (not sequentially)
- Identify that a touchpoint from weeks ago was crucial
- Model individual heterogeneity in touchpoint effects

**Architecture:**
```
Touchpoints → Embedding + Positional Encoding → Multi-Head Self-Attention →
  Feed Forward → [Repeat N times] → Pooling → Dense → Sigmoid
```

**Key Advantage:** Unlike LSTM which processes sequentially, transformers use self-attention to evaluate relationships between ALL touchpoints simultaneously. This excels at identifying non-linear customer behaviors.

**Configuration:**
| Option | Default | Description |
|--------|---------|-------------|
| `num_heads` | 4 | Number of attention heads |
| `num_layers` | 2 | Transformer encoder layers |
| `d_model` | 64 | Model dimension |
| `d_ff` | 128 | Feed-forward dimension |
| `max_seq_length` | 50 | Maximum journey length |

**Data Requirements:**
- Minimum: 10,000 conversions, 100,000 journeys
- Transformers are more data-hungry than LSTMs

#### 3.6.3 CNN for Pattern Recognition

**Algorithm:** 1D Convolutional Neural Network

CNNs can discover touchpoint sequence patterns:
- "Customers who visit pricing → testimonials → pricing have 87% conversion probability"
- Patterns too subtle for rule-based models

**Best for:** Identifying specific channel sequence patterns (motifs)

**Configuration:**
| Option | Default | Description |
|--------|---------|-------------|
| `filters` | [32, 64] | Conv layer filter counts |
| `kernel_sizes` | [3, 5] | Pattern lengths to detect |
| `pool_size` | 2 | Max pooling size |

### 3.7 Neural Network Attribution Methods

Computing attribution from neural networks requires post-hoc interpretability methods:

| Method | Speed | Accuracy | LSTM Compatible | Best For |
|--------|-------|----------|-----------------|----------|
| **Attention Weights** | Fast | Good | ✅ Native | Real-time, interpretable |
| **Integrated Gradients** | Slow | Excellent | ✅ Yes | Principled attribution |
| **SHAP (DeepExplainer)** | Very Slow | Excellent | ⚠️ Limited | Model-agnostic |
| **DeepLIFT** | Fast | Good | ❌ Issues with gates | CNNs, dense networks |

#### Attention Weights (Recommended for Real-Time)
```python
# Attribution directly from attention layer
touchpoint_credits = attention_weights * conversion_value
```
- ✅ Fast, interpretable, available during inference
- ❌ Not theoretically principled (attention ≠ importance)

#### Integrated Gradients (Recommended for Accuracy)
```python
# Compute gradients along path from baseline to input
baseline = zero_embedding  # or average journey
attributions = integrate(gradients(output, input), baseline, input, steps=50)
```
- ✅ Satisfies key axioms (Sensitivity, Implementation Invariance)
- ✅ Works correctly with LSTM multiplicative gates
- ❌ Requires ~50 forward passes per attribution (slow)

**Reference:** Sundararajan et al., "Axiomatic Attribution for Deep Networks"

#### SHAP Values
```python
# Model-agnostic Shapley value approximation
import shap
explainer = shap.DeepExplainer(model, background_data)
shap_values = explainer.shap_values(journey)
```
- ✅ Theoretically grounded (game theory)
- ❌ Computationally expensive
- ⚠️ DeepExplainer has limitations with built-in PyTorch LSTM

### 3.8 Neural Network Trade-offs Summary

| Aspect | LSTM+Attention | Transformer | CNN |
|--------|----------------|-------------|-----|
| **Accuracy** | High (80-85%) | Highest (85-90%) | Good (75-80%) |
| **Data Required** | 5,000+ conv | 10,000+ conv | 3,000+ conv |
| **Training Time** | Medium | Long | Short |
| **Interpretability** | Good (attention) | Good (attention) | Poor |
| **Long-range Deps** | Good | Excellent | Limited |
| **Pattern Detection** | Good | Good | Excellent |
| **Real-time Inference** | Fast | Medium | Fast |

**Recommendation:**
1. Start with LSTM+Attention (most balanced)
2. Upgrade to Transformer if data volume supports it
3. Use CNN as ensemble member for pattern detection

---

## 4. Storage: Extend AttributionModel

Use existing `attribution_models` table with new fields:

```
attribution_models:
  + model_tier: integer (heuristic: 0, probabilistic: 1, ml: 2)
  + training_status: integer (not_required: 0, pending: 1, training: 2, ready: 3, failed: 4)
  + trained_at: datetime
  + training_data_hash: string (detects staleness)
  + model_blob: binary (serialized trained model)
  + model_metrics: jsonb (gm, auc, tpr, tnr, feature_importance)
  + retrain_scheduled_at: datetime
  + preprocessing_config: jsonb (smote, class_weights, etc.)
```

**Benefits:**
- One model = one record (no separate training jobs table)
- Leverages existing account relationship
- Consistent with current model selector pattern
- Version tracking via existing `version` field

---

## 5. ML Workflow

### 5.1 Training Lifecycle

```
IDLE → PENDING → PREPROCESSING → TRAINING → VALIDATING → READY → (STALE) → RETRAINING
                      ↓              ↓           ↓
                   FAILED         FAILED      FAILED (metrics below threshold)
```

### 5.2 Training Triggers

| Trigger | Action |
|---------|--------|
| User clicks "Train Model" | Queue training job |
| Data grows 50% since last train | Mark as stale, prompt retrain |
| 90 days since last training | Mark as stale, auto-schedule retrain |
| Training fails | Notify user, keep previous version active |
| Validation fails (GM < threshold) | Notify user, suggest more data or different model |

### 5.3 Retraining Schedule

| Model Type | Auto-Retrain Interval | Staleness Threshold |
|------------|----------------------|---------------------|
| Bayesian Network | 90 days | 50% data growth |
| Logistic Regression | 90 days | 50% data growth |
| Additive Hazard | 90 days | 50% data growth |
| Gradient Boosting | 60 days | 30% data growth |
| Neural Network | 60 days | 30% data growth |
| Lead Scoring | 30 days | 20% data growth |

### 5.4 Rescoring Workflow

When model retrains:
1. Keep old model active during training
2. Validate new model meets GM threshold
3. On success: swap to new model atomically
4. Recompute attribution for last 90 days (background job)
5. Old credits marked with previous `model_version`

### 5.5 Model Versioning

- Each training produces new version: `v{YYYYMMDD}.{sequence}`
- Credits store `model_version` for audit trail
- Dashboard shows "Credits calculated with model v2025.01.15"
- Option to recompute historical credits with new model

---

## 6. Architecture

### 6.1 Rails (Probabilistic Models)

Markov Chain, Shapley, and optionally Bayesian Network implemented in Ruby.

```
app/services/attribution/algorithms/
├── markov_chain.rb
├── shapley_value.rb
├── ordered_shapley.rb
└── bayesian_network.rb (or delegate to Python)
```

### 6.2 Python Sidecar (ML Models)

**Why Python:**
- scikit-learn, XGBoost, lifelines (survival), pgmpy (Bayesian), PyTorch/TensorFlow
- imblearn for SMOTE and imbalanced data handling
- Industry-standard ML tooling
- Independent scaling from web tier

**Service:**
- FastAPI with `/train`, `/predict`, `/status`, `/validate` endpoints
- Reads from shared PostgreSQL
- Returns trained model blob + metrics

**Endpoints:**
```
POST /train
  - model_type: string
  - account_id: string
  - preprocessing: {smote: bool, class_weights: bool}
  - config: model-specific options

POST /predict
  - model_id: string
  - journeys: array of touchpoint sequences

GET /validate/{model_id}
  - Returns: {gm, auc, tpr, tnr, confusion_matrix}

POST /next-best-channel
  - model_id: string
  - current_journey: array of touchpoints
  - Returns: {recommended_channel, probability_lift}
```

**Deployment:**
- Docker container alongside Rails
- Kamal accessory
- Internal network only (not public)

### 6.3 Communication Flow

```
User clicks "Train" → Rails creates job → Python preprocesses (SMOTE) →
  Python trains → Python validates → Webhook callback → Rails stores model

User requests attribution → Rails calls Python /predict → Returns credits

Real-time scoring → Rails calls /next-best-channel → Returns recommendation
```

---

## 7. Cost Analysis

### 7.1 Infrastructure Costs

| Component | Monthly Cost | Notes |
|-----------|-------------|-------|
| Python service (idle) | ~$5-10 | Minimal when not training |
| Training job (per run) | ~$0.50-2 | CPU burst for 1-2 hours |
| Neural network training | ~$2-10 | GPU recommended for large datasets |
| Model storage | Negligible | ~100KB-5MB per trained model |

### 7.2 Pricing Strategy

| Plan | Tier 1 (Heuristic) | Tier 2 (Probabilistic) | Tier 3 (ML) | Neural Network | Lead Scoring |
|------|-------------------|------------------------|-------------|----------------|--------------|
| Free | ✓ | ✓ | ✗ | ✗ | ✗ |
| Starter | ✓ | ✓ | ✓ (1 retrain/month) | ✗ | ✗ |
| Pro | ✓ | ✓ | ✓ (unlimited) | ✓ | ✓ |
| Enterprise | ✓ | ✓ | ✓ (unlimited) | ✓ | ✓ |

**Rationale:**
- Free tier: Heuristic + Probabilistic (no server cost, strong value prop)
- ML models: Paid plans only (compute cost, high lock-in value)
- Neural Network: Pro+ only (highest compute, highest accuracy)
- Lead Scoring: Pro+ only (premium feature, highest value)

### 7.3 Compute Optimization

- Train during off-peak hours
- Batch multiple accounts if training simultaneously
- Cache Markov/Shapley/BN results (recompute only on data change)
- Use GPU spot instances for neural network training

---

## 8. AML Integration

### 8.1 New Functions

```ruby
# Attribution models
apply_model(:markov_chain)                    # Use probabilistic model
apply_model(:bayesian_network)                # Use Bayesian network
apply_model(:logistic_regression)             # Use trained ML model
apply_model(:neural_network)                  # Use LSTM model

# Model management
model_available?(:logistic_regression)        # Check if model ready
model_metrics(:gradient_boosting)             # Get GM, AUC, etc.

# Prediction
conversion_probability(touchpoints)           # Get lead score (0-100)
next_best_channel(touchpoints)                # Get recommended next channel

# Advanced
blend_models([{model: :markov, weight: 0.6}, {model: :bayesian, weight: 0.4}])
```

### 8.2 Validation

- Probabilistic models: Validate data threshold met
- ML models: Validate model is trained, not stale, and meets GM threshold
- Return clear error if model unavailable
- Warn if model metrics are below recommended thresholds

---

## 9. UX Flow

### 9.1 Model Selector

```
HEURISTIC MODELS (always available)
├── First Touch, Last Touch, Linear...

PROBABILISTIC MODELS
├── Markov Chain      ✓ Ready (847 conversions) | GM: 0.59
├── Shapley Value     ✓ Ready | GM: 0.57
├── Bayesian Network  ✓ Ready | GM: 0.63

MACHINE LEARNING MODELS
├── Logistic Regression  ⚠ Need 1,153 more conversions
├── Gradient Boosting    ⚠ Need 2,153 more conversions
├── Neural Network       ⚠ Need 4,153 more conversions
└── [View Requirements]
```

### 9.2 Data Requirements Page

Shows:
- Progress bars for each threshold
- Estimated time to reach threshold (based on current velocity)
- Current conversion rate (with imbalanced data warning if < 2%)
- "Notify me when ready" option
- "Request Training" button when ready

### 9.3 Training Status

```
Training in progress... (started 45 min ago)
├── ✓ Data preprocessing (SMOTE applied)
├── ✓ Model training
├── ◐ Validation (checking metrics...)
Estimated completion: 15 minutes
You'll receive an email when ready.
```

### 9.4 Model Metrics Display

```
Gradient Boosting v2025.01.15
├── Geometric Mean: 0.62 ✓
├── AUC-ROC: 0.78 ✓
├── Sensitivity (TPR): 0.58
├── Specificity (TNR): 0.66
├── Trained on: 3,247 conversions
└── Last updated: 15 days ago
```

---

## 10. Documentation Touchpoints

| Location | Content |
|----------|---------|
| Homepage | Model tiers feature section |
| Onboarding | Step explaining model progression |
| Docs: /attribution-models | Overview of all models |
| Docs: /attribution-models/markov | Deep dive on Markov Chain |
| Docs: /attribution-models/bayesian | Deep dive on Bayesian Network |
| Docs: /attribution-models/neural | Deep dive on Neural Networks |
| Docs: /data-requirements | Imbalanced data, preprocessing, metrics |
| Model selector | Tooltips with descriptions + requirements |
| Dashboard widget | Data readiness progress + model metrics |

---

## 11. Implementation Phases

### Phase 1: Foundation
- Add model tier fields to AttributionModel
- Create DataReadinessChecker service
- Update model selector UI
- Add imbalanced data detection + warnings

### Phase 2: Probabilistic Models
- Implement Markov Chain in Ruby
- Implement Shapley Value in Ruby
- Implement Bayesian Network (Ruby or Python)
- Add AML `apply_model()` function
- Add validation metrics calculation

### Phase 3: Training Infrastructure
- Add training status fields to AttributionModel
- Build data requirements UI
- Implement training request flow
- Add SMOTE and preprocessing pipeline

### Phase 4: Python Sidecar
- FastAPI service with train/predict/validate endpoints
- LogisticRegression and AdditiveHazard models
- Gradient Boosting (XGBoost/LightGBM)
- Docker + Kamal deployment

### Phase 5: ML Workflow
- Retraining scheduler
- Staleness detection
- Model versioning and credit recomputation
- Validation threshold enforcement

### Phase 6: Advanced Models
- Hidden Markov Model
- Neural Network (LSTM with attention)
- Next best channel prediction
- Model blending

### Phase 7: Lead Scoring
- Conversion probability model
- API endpoint for visitor scoring
- Real-time journey scoring
- Dashboard integration

---

## 12. Sources

### Academic Papers
- Ben Mrad & Hnich (2024) - "Intelligent attribution modeling for enhanced digital marketing performance" - Bayesian networks, imbalanced data handling
- Anderl et al. (2016) - "Mapping the customer journey" - Markov chain attribution
- Abhishek et al. (2012) - "Media exposure through the funnel" - Hidden Markov models
- Shao & Li (2011) - "Data-driven multi-touch attribution models" - Bagged logistic regression
- Zhang et al. (2014) - "Multi-touch attribution with survival theory" - Additive hazard models
- Li & Kannan (2014) - "Attributing conversions in a multichannel environment" - Hierarchical Bayes
- Xu et al. (2014) - "Path to purchase" - Mutually exciting point process
- Gupta et al. (2020) - "Digital Analytics: Modeling for Insights and New Methods"

### Industry Resources
- [Markov Chain Attribution - Triple Whale](https://www.triplewhale.com/blog/markov-chain-attribution)
- [Multi-Touch Attribution with Survival Theory - UCL](http://www0.cs.ucl.ac.uk/staff/w.zhang/rtb-papers/attr-survival.pdf)
- [Shapley Value Methods - arXiv](https://arxiv.org/abs/1804.05327)
- [MTA Python Library](https://github.com/eeghor/mta)
- [Google DDA Requirements](https://support.google.com/google-ads/answer/6394265)
- [SMOTE - imbalanced-learn](https://imbalanced-learn.org/stable/references/generated/imblearn.over_sampling.SMOTE.html)
