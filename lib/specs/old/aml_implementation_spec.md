# AML (Attribution Modeling Language) Implementation Spec

**Status**: ✅ Complete
**Created**: 2025-12-08
**Completed**: 2025-12-09

---

## Overview

AML is a Ruby-based DSL for defining custom attribution models. This spec outlines the test-driven implementation approach with security as the primary concern.

---

## Open Questions / Requirements Needed

> **Note**: W-Shaped attribution was removed from the product (2025-12-08). It required "lead creation" touchpoint identification that conflicts with our visitor-based tracking model. B2B users who need funnel stage tracking should use multiple conversion types (MQL, SQL, Opportunity, Closed Won) instead.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AML Execution Pipeline                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  User Code ──► Parser ──► AST ──► Validator ──► Executor ──► Result │
│                  │          │         │            │                │
│                  ▼          ▼         ▼            ▼                │
│              Syntax     Security  Credit Sum   Sandbox              │
│              Check      Analysis  Validation   Execution            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
app/services/aml/
├── executor.rb                  # Execute validated AML safely
├── errors.rb                    # AML-specific error classes
│
├── security/
│   ├── whitelist.rb             # Allowed methods, constants, operators
│   └── ast_analyzer.rb          # Walk AST, detect forbidden operations (includes parsing)
│
├── sandbox/
│   ├── context.rb               # BasicObject-based safe execution context
│   ├── touchpoint_collection.rb # Array with iteration limits
│   ├── safe_touchpoint.rb       # Read-only touchpoint wrapper
│   ├── credit_assigner.rb       # Credit assignment logic
│   ├── credit_ledger.rb         # Track and validate credits
│   └── time_decay_calculator.rb # Time decay implementation
│
└── templates.rb                 # Standard model AML definitions

test/services/aml/
├── executor_test.rb
├── templates_test.rb
│
└── security/
    ├── whitelist_test.rb
    ├── ast_analyzer_test.rb
    ├── command_injection_test.rb
    ├── file_system_test.rb
    ├── network_access_test.rb
    ├── eval_metaprogramming_test.rb
    ├── constant_manipulation_test.rb
    ├── global_variables_test.rb
    └── sandbox_escape_test.rb
```

---

## Implementation Checklist

### Phase 1: Foundation & Security Layer ✅

#### 1.1 Project Setup
- [x] Add `parser` gem to Gemfile
- [x] Create `app/services/aml/` directory structure
- [x] Create `test/services/aml/` directory structure
- [x] Create `AML::Error` base exception class

#### 1.2 Security Whitelist (TDD)
- [x] Define `ALLOWED_ARRAY_METHODS` constant
- [x] Define `ALLOWED_STRING_METHODS` constant
- [x] Define `ALLOWED_NUMERIC_METHODS` constant
- [x] Define `ALLOWED_TIME_METHODS` constant
- [x] Define `ALLOWED_HASH_METHODS` constant
- [x] Define `ALLOWED_DSL_METHODS` constant
- [x] Define `FORBIDDEN_METHODS` constant
- [x] Define `FORBIDDEN_CONSTANTS` constant
- [x] Write tests for each whitelist category
- [x] Implement whitelist checker

#### 1.3 AST Analyzer Security Tests ✅
All attack vectors covered in dedicated test files:
- [x] Command Injection tests (10 tests)
- [x] File System Access tests (8 tests)
- [x] Network Access tests (6 tests)
- [x] Eval/Metaprogramming tests (12 tests)
- [x] Constant Manipulation tests (8 tests)
- [x] Global Variables tests (5 tests)
- [x] Sandbox Escape tests (10+ tests)

#### 1.4 AST Analyzer Implementation ✅
- [x] Implement `AML::Security::AstAnalyzer` class
- [x] Implement recursive AST walker
- [x] Detect `:send` nodes with forbidden methods
- [x] Detect `:const` nodes with forbidden constants
- [x] Detect `:xstr` nodes (backticks)
- [x] Detect `:gvar` nodes (global variables)
- [x] All security tests pass

---

### Phase 2: Parser & Validator ✅

> **Implementation Note**: Parser and Validator functionality consolidated into ASTAnalyzer and ValidationService for simpler architecture.

#### 2.1 Parser (via ASTAnalyzer)
- [x] Use `Parser::CurrentRuby.parse()` for parsing
- [x] Handle syntax errors with line/column info
- [x] Return structured AST representation
- [x] Write parser tests

#### 2.2 Validator (via ValidationService)
- [x] Integrate security AST analyzer
- [x] Validate credit assignments
- [x] Collect all errors (don't fail fast)
- [x] Write validator tests

---

### Phase 3: Sandbox & Execution ✅

#### 3.1 Safe Wrappers
- [x] Create `AML::Sandbox::TouchpointCollection` with iteration limits
- [x] Create `AML::Sandbox::SafeTouchpoint` (read-only)
- [x] Write tests for each wrapper

#### 3.2 DSL Methods
- [x] Implement `within_window(duration, &block)`
- [x] Implement `apply(credit, to:, distribute:)`
- [x] Implement `apply(to:, &block)` (block form)
- [x] Implement `time_decay(half_life:)`
- [x] Implement `normalize!`
- [x] Write tests for each DSL method

#### 3.3 Execution Context
- [x] Create `AML::Sandbox::Context < BasicObject`
- [x] Expose only safe methods
- [x] Block `method_missing` with SecurityError
- [x] Write context tests

#### 3.4 Executor
- [x] Create `AML::Executor` class
- [x] Integrate timeout (5 seconds)
- [x] Track iteration count
- [x] Execute within sandbox context
- [x] Validate result credits sum to 1.0
- [x] Handle execution errors gracefully
- [x] Write executor tests

---

### Phase 4: Integration ✅

#### 4.1 Standard Models as AML
- [x] First Touch AML definition
- [x] Last Touch AML definition
- [x] Linear AML definition
- [x] Time Decay AML definition
- [x] U-Shaped AML definition
- [x] Participation AML definition
- [x] Write integration tests for each

#### 4.2 Database Migration
- [x] Add `dsl_code` (text) column
- [x] Add `lookback_days` (integer) column
- [x] Run migration

#### 4.3 Model Integration
- [x] Update `AttributionModel` with AML methods
- [x] Add `execute(touchpoints, conversion)` method
- [x] Add validation callback for AML syntax
- [x] Write model tests

---

### Phase 5: Edge Cases & Hardening ✅

#### 5.1 Edge Case Handling
- [x] 0 touchpoints → empty result
- [x] 1 touchpoint → 100% credit
- [x] 2 touchpoints → handle U-shaped edge case
- [x] Division by zero protection
- [x] Empty filter results
- [x] Write edge case tests

#### 5.2 Error Handling
- [x] Graceful syntax error messages
- [x] Graceful security violation messages
- [x] Graceful execution timeout handling
- [x] Error logging for debugging
- [x] Write error handling tests

---

## Success Criteria ✅

### Security
- [x] All 50+ security tests pass
- [x] No sandbox escapes possible
- [x] All attack vectors blocked

### Functionality
- [x] All 6 preset models execute correctly via AML
- [x] Custom models can be defined and executed
- [x] Edge cases (0, 1, 2 touchpoints) handled
- [x] Credits always sum to 1.0 (or validate error)

### Performance
- [x] Execution < 100ms for typical models
- [x] Timeout enforced at 5 seconds
- [x] Memory usage bounded

### Developer Experience
- [x] Clear error messages with line/column info
- [x] Comprehensive test coverage (1510+ lines across 14 test files)

---

## Test Coverage Summary

- **Total test files**: 14
- **Total test lines**: 1510+
- **Security test files**: 7 dedicated files
- **Integration tests**: Standard models, custom models, edge cases

---

## References

- [aml_security_spec.md](../docs/aml_security_spec.md) - Security requirements (moved to docs)
- [attribution_dsl_design.md](../docs/attribution_dsl_design.md) - DSL syntax design (moved to docs)
- [attribution_dsl_plan.md](../docs/attribution_dsl_plan.md) - AST node design (moved to docs)
