# Attribution Model Declarative Language (DSL) - Design Spec

**Status**: Design Phase - To Be Implemented in Phase 2C

---

## Vision

Create a **true declarative language** for defining custom attribution models, not just YAML configuration. Users should be able to express attribution logic in a readable, composable way.

---

## Inspiration: Rule Engine DSL Examples

### Example 1: Drools-style (Business Rules)
```
rule "First Touch Attribution"
when
  touchpoint: position == first
then
  assign credit 1.0 to touchpoint
end

rule "Paid Channels Bonus"
when
  touchpoint: channel matches /paid_.*/
then
  multiply credit by 1.5
end
```

### Example 2: SQL-like Declarative
```sql
DEFINE MODEL weighted_paid
  SELECT session,
         CASE
           WHEN channel LIKE 'paid_%' THEN 1.5
           WHEN channel = 'email' THEN 1.2
           ELSE 1.0
         END as weight
  FROM journey_sessions
  DISTRIBUTE credit BY weight
```

### Example 3: Functional DSL (Ruby-based)
```ruby
model :custom_weighted do
  weight_by :channel do |ch|
    case ch
    when /^paid_/ then 1.5
    when 'email' then 1.2
    else 1.0
    end
  end

  distribute :weighted
end

model :u_shaped do
  assign 0.4, to: :first
  assign 0.4, to: :last
  assign 0.2, to: :middle, distribute: :equal
end
```

---

## Requirements

### 1. Declarative, Not Imperative
- Users describe **what** they want, not **how** to compute it
- No loops, no variables, no procedural logic
- Pure expression of attribution rules

### 2. Composable
- Combine multiple rules
- Layer conditions and weights
- Reuse building blocks

### 3. Type-Safe
- Credits must sum to 1.0 (enforced by parser)
- Validate at definition time, not runtime
- Clear error messages

### 4. Readable
- Non-technical marketers can understand it
- Visual builder can generate valid DSL
- DSL can be displayed as human-readable text

### 5. Powerful Enough
- Support all 11 standard models
- Allow custom business logic (channel weighting, event-based triggers, time-based decay)
- Support future extensions (conversion value weighting, user segments, etc.)

---

## Proposed DSL Syntax (Draft)

### Option A: Expression-Based DSL

```
model "U-Shaped Attribution"
  credit first_touch with 0.4
  credit last_touch with 0.4
  credit middle_touches with 0.2 distributed equally
end

model "Channel Weighted"
  weight paid_search by 1.5
  weight paid_social by 1.3
  weight email by 1.2
  distribute credit proportionally
end

model "W-Shaped"
  credit first_touch with 0.3
  credit last_touch with 0.3
  credit event(type: "opportunity_created") with 0.3
  credit remaining with 0.1 distributed equally
end

model "Custom Time Decay"
  for each touch in journey
    credit with decay(half_life: 14.days)
  end
  normalize to 1.0
end
```

### Option B: Constraint-Based DSL

```
model "Participation with Bonus" where
  base_credit = 1.0 / journey.length

  for touch in journey:
    channel(paid_search) => base_credit * 1.5
    channel(email) => base_credit * 1.2
    default => base_credit

  ensure sum(credits) == 1.0
end
```

### Option C: Pattern Matching DSL

```
attribution_model do
  match position: :first   => credit(0.4)
  match position: :last    => credit(0.4)
  match position: :middle  => credit(0.2, distribute: :equal)

  validate sum: 1.0
end

attribution_model do
  match channel: /^paid_/  => multiply(1.5)
  match channel: 'email'   => multiply(1.2)
  match :all               => distribute(:weighted)

  validate sum: 1.0
end
```

---

## Implementation Strategy

### Phase 1: Parser & AST (Abstract Syntax Tree)
- Lexer: Tokenize DSL text
- Parser: Build AST from tokens
- Validator: Ensure credits sum to 1.0, syntax valid

### Phase 2: Interpreter
- Traverse AST
- Execute against journey_sessions
- Return attribution_credits

### Phase 3: Visual Builder
- Drag-and-drop rule builder
- Generates valid DSL code
- Live preview with sample journey

### Phase 4: Storage
- Store DSL text in `attribution_models.dsl_code` (text column)
- Store compiled AST in `attribution_models.rules` (jsonb) for performance
- Recompile on edit

---

## Technical Architecture

```
app/services/attribution/dsl/
├── lexer.rb              # Tokenize DSL text
├── parser.rb             # Build AST from tokens
├── ast/
│   ├── node.rb           # Base AST node
│   ├── model_node.rb     # Model definition
│   ├── rule_node.rb      # Credit/weight rule
│   ├── condition_node.rb # Match condition
│   └── expression_node.rb # Mathematical expression
├── validator.rb          # Validate AST (credits sum to 1.0)
├── interpreter.rb        # Execute AST against journey
├── compiler.rb           # Compile to optimized bytecode (optional)
└── error.rb              # DSL-specific errors

app/models/attribution_model.rb
  - dsl_code (text) - Source DSL
  - rules (jsonb) - Compiled AST
  - compile! - Parse dsl_code → rules
  - validate_dsl - Ensure valid syntax
```

---

## Examples: Standard Models in DSL

### First Touch
```
model "First Touch"
  credit first_touch with 1.0
end
```

### Linear (Participation)
```
model "Linear"
  credit all_touches equally
end
```

### Time Decay
```
model "Time Decay"
  for each touch in journey
    credit with exponential_decay(half_life: 7.days)
  end
end
```

### U-Shaped
```
model "U-Shaped"
  credit first_touch with 0.4
  credit last_touch with 0.4
  credit middle_touches with 0.2 equally
end
```

### W-Shaped
```
model "W-Shaped"
  credit first_touch with 0.3
  credit last_touch with 0.3
  credit event("opportunity_created") with 0.3
  credit remaining with 0.1 equally
end
```

### Z-Shaped (B2B)
```
model "Z-Shaped"
  credit first_touch with 0.225
  credit event("mql_conversion") with 0.225
  credit event("sql_conversion") with 0.225
  credit last_touch with 0.225
  credit remaining with 0.1 equally
end
```

### Custom Weighted
```
model "Weighted by Channel"
  weight channel("paid_search") by 1.5
  weight channel("paid_social") by 1.3
  weight channel("email") by 1.2
  distribute proportionally
end
```

---

## Visual Builder → DSL Generation

**UI Flow**:
1. User clicks "Create Custom Model"
2. Drag-and-drop rules: "First Touch gets 40%", "Last Touch gets 40%", etc.
3. Live preview shows DSL code
4. User can edit DSL directly OR use visual builder
5. Save → validates → compiles to AST → stores in DB

**Example UI → DSL**:
```
Visual Builder:
┌────────────────────────────┐
│ Rule 1: First Touch        │
│ Credit: [40%]              │
├────────────────────────────┤
│ Rule 2: Last Touch         │
│ Credit: [40%]              │
├────────────────────────────┤
│ Rule 3: Middle Touches     │
│ Credit: [20%]              │
│ Distribution: [Equal ▼]    │
└────────────────────────────┘

Generated DSL:
model "My Custom Model"
  credit first_touch with 0.4
  credit last_touch with 0.4
  credit middle_touches with 0.2 equally
end
```

---

## Future Extensions

### 1. Conditional Logic
```
model "Conditional Attribution"
  if conversion_value > 1000
    credit last_touch with 0.6
    credit first_touch with 0.4
  else
    credit all_touches equally
  end
end
```

### 2. Segment-Based Attribution
```
model "Segment Weighted"
  for touch in journey where
    if visitor.segment == "enterprise"
      weight by 2.0
    elsif visitor.segment == "smb"
      weight by 1.0
    end
  end
  distribute proportionally
end
```

### 3. Channel Transition Bonuses
```
model "Transition Bonus"
  for each transition in journey
    if from("organic_search") to("paid_search")
      bonus 0.1
    end
  end
  distribute remaining proportionally
end
```

---

## Decision: DSL Syntax Choice

**Recommendation**: Start with **Option C (Pattern Matching DSL)** because:
1. Most Ruby-like (familiar to developers)
2. Easy to parse and validate
3. Clear separation of conditions and actions
4. Extensible for future features

**Alternative**: Create a **hybrid approach**:
- Simple models: Use pattern matching DSL
- Complex models: Allow embedded Ruby blocks (sandboxed)
- Visual builder: Generates pattern matching DSL

---

## Implementation Priority

### Phase 2B (Week 2): Preset Models Only
- Implement 7 preset models as hardcoded services
- No DSL yet

### Phase 2C (Week 3-4): DSL Development
- Design final DSL syntax (based on this spec)
- Implement lexer, parser, AST, interpreter
- Build visual model builder UI
- Support custom models via DSL

### Phase 3+: Advanced Features
- Conditional logic
- Segment-based attribution
- Machine learning models (algorithmic, Markov, Shapley)

---

## Success Criteria

**DSL Language**:
- [ ] Non-technical users can read and understand DSL
- [ ] DSL is type-safe (enforces credits sum to 1.0)
- [ ] Visual builder generates valid DSL
- [ ] DSL can be edited directly by power users
- [ ] Error messages are clear and actionable

**Implementation**:
- [ ] Parser handles all standard models
- [ ] Interpreter executes correctly against journey
- [ ] Compiled AST stored for performance
- [ ] 95%+ test coverage on DSL engine

**User Experience**:
- [ ] Create custom model in <5 minutes via visual builder
- [ ] Preview attribution with sample journey
- [ ] Export/import models as DSL text
- [ ] Share models across accounts (marketplace?)

---

**Next Step**: Choose DSL syntax, build parser prototype, validate with sample models.
