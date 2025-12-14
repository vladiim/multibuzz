# Attribution Model Editor DSL - Design Plan

## Overview

A SQL-like DSL for defining custom attribution models with broad flexibility while maintaining guard rails (credits sum to 1.0, valid ranges, etc.).

---

## 1. Existing Model Patterns Analysis

| Model | Core Logic | Key Constructs Needed |
|-------|------------|----------------------|
| **First Touch** | `touchpoints[0]` gets 1.0 | Position selection |
| **Last Touch** | `touchpoints[-1]` gets 1.0 | Position selection (negative index) |
| **Linear** | `1.0 / count` to each | Distribute equally |
| **Time Decay** | `2^(-days/half_life)` | Decay function, time math |
| **U-Shaped** | first=0.4, last=0.4, middle=0.2 | Position weights, distribute remainder |
| **Participation** | 1.0 per unique channel | Group by channel, no normalization |

---

## 2. AST Node Types

### 2.1 Core Node Structure

```ruby
# Every node carries location for error messages
BaseNode = Struct.new(:line, :column, :length, keyword_init: true)
```

### 2.2 Top-Level Nodes

```ruby
ModelDefinition < BaseNode
  name: String
  description: String?
  lookback_window: WindowExpr?
  rules: [RuleNode]
  validations: [ValidationNode]
end
```

### 2.3 Rule Nodes

```ruby
# Credit assignment rule
CreditRule < BaseNode
  target: TargetExpr        # WHO gets credit
  amount: AmountExpr        # HOW MUCH credit
  condition: ConditionExpr? # WHEN (optional filter)
end

# Weight rule (for weighted distribution)
WeightRule < BaseNode
  target: TargetExpr
  weight: NumericExpr
end
```

### 2.4 Target Expression Nodes (WHO gets credit)

```ruby
# Position-based selection
PositionTarget < BaseNode
  position: :first | :last | :middle | :all
end

# Index-based selection
IndexTarget < BaseNode
  index: Integer  # supports negative (-1 = last)
end

# Range selection
RangeTarget < BaseNode
  start_index: Integer
  end_index: Integer  # exclusive, nil = end
end

# Channel-based selection
ChannelTarget < BaseNode
  channels: [String] | :all
end

# Filtered selection
FilteredTarget < BaseNode
  base: TargetExpr
  condition: ConditionExpr
end
```

### 2.5 Amount Expression Nodes (HOW MUCH credit)

```ruby
# Fixed credit value
FixedAmount < BaseNode
  value: Float  # 0.0 to 1.0
end

# Computed credit
ComputedAmount < BaseNode
  expression: :equal_share | :remaining | Expression
end

# Function-based credit
FunctionAmount < BaseNode
  function: :time_decay | :linear | :custom
  params: Hash
end

# Distribution modifier
DistributedAmount < BaseNode
  total: Float
  strategy: :equal | :weighted | :proportional
end
```

### 2.6 Condition Nodes (WHEN/WHERE filters)

```ruby
# Position condition
PositionCondition < BaseNode
  operator: :eq | :in | :not_in
  positions: [:first, :last, :middle]
end

# Channel condition
ChannelCondition < BaseNode
  operator: :eq | :in | :matches
  value: String | [String] | Regexp
end

# Time condition
TimeCondition < BaseNode
  operator: :within | :before | :after
  duration: DurationExpr
end

# Logical combinators
AndCondition < BaseNode
  left: ConditionExpr
  right: ConditionExpr
end

OrCondition < BaseNode
  left: ConditionExpr
  right: ConditionExpr
end
```

### 2.7 Expression Nodes

```ruby
# Numeric literal
NumericLiteral < BaseNode
  value: Float
end

# Duration literal
DurationLiteral < BaseNode
  value: Integer
  unit: :days | :hours | :minutes
end

# Binary expression
BinaryExpr < BaseNode
  operator: :add | :subtract | :multiply | :divide
  left: Expression
  right: Expression
end

# Variable reference
VariableRef < BaseNode
  name: :count | :total_credit | :remaining | :index | :days_before
end

# Function call
FunctionCall < BaseNode
  name: String
  arguments: [Expression]
end
```

### 2.8 Validation Nodes

```ruby
ValidationRule < BaseNode
  type: :sum_equals | :range | :required
  target: :credits | :weights
  value: Any
  message: String?
end
```

---

## 3. DSL Syntax Examples

### 3.1 First Touch
```sql
MODEL "First Touch"
  ASSIGN 1.0 TO FIRST
END
```

### 3.2 Last Touch
```sql
MODEL "Last Touch"
  ASSIGN 1.0 TO LAST
END
```

### 3.3 Linear
```sql
MODEL "Linear"
  ASSIGN EQUAL_SHARE TO ALL
END
```

### 3.4 Time Decay
```sql
MODEL "Time Decay"
  ASSIGN TIME_DECAY(half_life: 7 DAYS) TO ALL
END
```

### 3.5 U-Shaped
```sql
MODEL "U-Shaped"
  ASSIGN 0.4 TO FIRST
  ASSIGN 0.4 TO LAST
  ASSIGN REMAINING DISTRIBUTE EQUAL TO MIDDLE
END
```

### 3.6 Custom: Channel Bonus
```sql
MODEL "Paid Search Boost"
  ASSIGN 0.5 TO FIRST WHERE channel MATCHES 'paid_*'
  ASSIGN 0.3 TO LAST
  ASSIGN REMAINING DISTRIBUTE EQUAL TO ALL
END
```

### 3.8 Custom: Recency Weighted
```sql
MODEL "Recency Weighted"
  WEIGHT 2.0 WHERE position = LAST
  WEIGHT 1.5 WHERE days_before < 3
  WEIGHT 1.0 TO ALL
  ASSIGN PROPORTIONAL TO ALL
END
```

---

## 4. Key DSL Constructs

### 4.1 Position Selectors
```
FIRST          -- touchpoints[0]
LAST           -- touchpoints[-1]
MIDDLE         -- touchpoints[count/2] (single)
MIDDLE_ALL     -- touchpoints[1..-2] (range, excludes first/last)
OTHERS         -- all except explicitly assigned
ALL            -- every touchpoint
INDEX(n)       -- touchpoints[n]
RANGE(a, b)    -- touchpoints[a..b]
```

### 4.2 Credit Assignment
```
ASSIGN <amount> TO <target> [WHERE <condition>]

<amount> ::=
  | <number>                    -- fixed: 0.4
  | EQUAL_SHARE                 -- 1.0 / count
  | REMAINING                   -- 1.0 - already_assigned
  | REMAINING DISTRIBUTE EQUAL  -- split remainder equally
  | TIME_DECAY(half_life: N DAYS)
  | PROPORTIONAL                -- based on weights
```

### 4.3 Weight Assignment (for proportional)
```
WEIGHT <number> TO <target> [WHERE <condition>]

-- Weights are normalized to sum to 1.0, then multiplied by available credit
```

### 4.4 Conditions
```
WHERE channel = 'paid_search'
WHERE channel IN ('paid_search', 'paid_social')
WHERE channel MATCHES 'paid_*'
WHERE position = FIRST
WHERE position IN (FIRST, LAST)
WHERE days_before < 7
WHERE days_before BETWEEN 0 AND 3
```

### 4.5 Time/Window
```
WITHIN 30 DAYS           -- lookback window
HALF_LIFE 7 DAYS         -- for time decay
```

### 4.6 Built-in Functions
```
TIME_DECAY(half_life: N DAYS)  -- exponential decay
LINEAR()                        -- equal share
POSITION_BASED(first: 0.4, last: 0.4, middle: 0.2)
```

---

## 5. Edge Cases & Validation

### 5.1 Edge Cases to Handle
| Touchpoints | First Touch | Linear | U-Shaped |
|-------------|-------------|--------|----------|
| 0 | [] | [] | [] |
| 1 | [1.0] | [1.0] | [1.0] |
| 2 | [1.0, 0] | [0.5, 0.5] | [0.5, 0.5] |
| 3 | [1.0, 0, 0] | [0.33, 0.33, 0.33] | [0.4, 0.2, 0.4] |
| 4+ | [1.0, 0, ...] | [0.25, ...] | [0.4, 0.1, 0.1, 0.4] |

### 6.2 Validation Rules
1. **Sum validation**: Credits must sum to 1.0 (±0.0001 tolerance)
2. **Range validation**: Each credit 0.0 ≤ x ≤ 1.0
3. **Coverage**: All touchpoints must receive a credit (even if 0)
4. **No duplicate targets**: Can't assign twice to same position without merge strategy

### 6.3 Error Messages

```
Error at line 3, column 10:
  ASSIGN 0.5 TO FIRST
         ^^^
Credits sum to 1.3 but must equal 1.0
  Current assignments:
    FIRST:  0.5
    LAST:   0.5
    MIDDLE: 0.3
  Suggestion: Reduce one assignment by 0.3
```

---

## 7. Compiler Pipeline

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Source    │───▶│   Lexer     │───▶│   Parser    │───▶│  Validator  │
│   (DSL)     │    │  (Tokens)   │    │   (AST)     │    │ (Typed AST) │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                                │
                                                                ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Execute    │◀───│  Optimize   │◀───│  Compile    │◀───│   Resolve   │
│ (Credits)   │    │ (Simplify)  │    │ (Bytecode)  │    │ (Functions) │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

### 7.1 Stages

1. **Lexer**: Text → Tokens (with line/column info)
2. **Parser**: Tokens → AST (syntax validation)
3. **Validator**: AST → Typed AST (semantic validation, type checking)
4. **Resolver**: Resolve function references, calculate REMAINING
5. **Compiler**: AST → Executable form (JSONB or bytecode)
6. **Optimizer**: Simplify redundant rules, pre-compute constants
7. **Executor**: Run against touchpoints, return credits array

---

## 8. Storage Format

Store compiled AST as JSONB for fast execution:

```json
{
  "version": 1,
  "name": "U-Shaped",
  "rules": [
    {"type": "credit", "target": {"type": "position", "value": "first"}, "amount": 0.4},
    {"type": "credit", "target": {"type": "position", "value": "last"}, "amount": 0.4},
    {"type": "credit", "target": {"type": "position", "value": "middle"}, "amount": {"type": "remaining", "distribute": "equal"}}
  ],
  "validations": [
    {"type": "sum_equals", "value": 1.0}
  ]
}
```

---

## 9. Implementation Phases

### Phase 1: AST Foundation
- [ ] Define all node types as Ruby classes
- [ ] Implement Visitor pattern for traversal
- [ ] Add location tracking to all nodes

### Phase 2: Lexer
- [ ] Tokenize keywords (MODEL, ASSIGN, TO, WHERE, etc.)
- [ ] Handle literals (numbers, strings, durations)
- [ ] Track line/column positions

### Phase 3: Parser
- [ ] Recursive descent parser
- [ ] Build AST from token stream
- [ ] Collect syntax errors (don't fail fast)

### Phase 4: Validator
- [ ] Type checking
- [ ] Sum validation
- [ ] Range validation
- [ ] Helpful error messages with suggestions

### Phase 5: Executor
- [ ] Interpret AST against touchpoints
- [ ] Handle edge cases (0, 1, 2 touchpoints)
- [ ] Return credits array

### Phase 6: Integration
- [ ] Store DSL source + compiled JSONB
- [ ] Visual editor UI
- [ ] Migrate existing preset models to DSL

---

## 10. Open Questions

1. **Should PARTICIPATION model be supported?** (credits don't sum to 1.0)
2. **Allow custom functions?** (user-defined, sandboxed)
3. **Support conditionals?** (IF conversion_value > 100 THEN ...)
4. **Channel transitions?** (bonus for paid → organic flow)
5. **Segment-based rules?** (WHERE visitor.segment = 'enterprise')
