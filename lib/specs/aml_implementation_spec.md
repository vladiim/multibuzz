# AML (Attribution Modeling Language) Implementation Spec

**Status**: Implementation Phase
**Created**: 2025-12-08
**Last Updated**: 2025-12-08

---

## Overview

AML is a Ruby-based DSL for defining custom attribution models. This spec outlines the test-driven implementation approach with security as the primary concern.

---

## Open Questions / Requirements Needed

### W-Shaped Attribution: Stage/Milestone Definition

**BLOCKER**: W-shaped attribution requires identifying "key milestones" in the customer journey (e.g., MQL, SQL, Opportunity creation). We need user input on how stages should be defined.

**Options to discuss with user:**

1. **Stage as event type string**
   ```ruby
   # User defines stages when creating the model
   stages: ["mql_conversion", "sql_conversion", "opportunity_created"]

   # In AML:
   apply 0.3 to touchpoints.find { |tp| tp.event_type == "mql_conversion" }
   ```

2. **Stage as integer (funnel position)**
   ```ruby
   # Touchpoints have a stage integer (0 = awareness, 1 = consideration, etc.)
   apply 0.3 to touchpoints.find { |tp| tp.stage == 1 }
   ```

3. **Named stages array on conversion**
   ```ruby
   # Conversion has stages: ["mql", "sql", "opportunity"]
   stages.each do |stage_event|
     apply 0.3 / stages.length to touchpoints.find { |tp| tp.event_type == stage_event }
   end
   ```

4. **Stage markers in journey**
   ```ruby
   # Journey has explicit stage markers
   journey.stage(:mql)  # Returns touchpoint that triggered MQL
   journey.stage(:sql)  # Returns touchpoint that triggered SQL

   apply 0.3 to journey.stage(:mql)
   apply 0.3 to journey.stage(:sql)
   ```

**Questions for user:**
- How do customers define their funnel stages today?
- Should stages be account-level configuration or per-model?
- Are stages always event types, or can they be based on properties?
- Should we support "closest touchpoint to stage" for when exact match isn't found?

**Recommended approach:** Option 3 or 4 - explicit stage configuration with event_type matching.

**Database impact:**
```ruby
# Possible migration
add_column :attribution_models, :stage_events, :jsonb, default: []
# Or
add_column :conversions, :stage_events, :jsonb, default: {}
# e.g., { "mql": "evt_123", "sql": "evt_456" }
```

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
├── parser.rb                    # Parse AML code → Parser AST
├── validator.rb                 # Validate AST (security + semantics)
├── executor.rb                  # Execute validated AML safely
├── compiler.rb                  # Compile AST → JSONB for storage
├── errors.rb                    # AML-specific error classes
│
├── security/
│   ├── whitelist.rb             # Allowed methods, constants, operators
│   ├── ast_analyzer.rb          # Walk AST, detect forbidden operations
│   └── forbidden_patterns.rb    # Regex patterns for dangerous code
│
├── sandbox/
│   ├── context.rb               # BasicObject-based safe execution context
│   ├── safe_array.rb            # Array with iteration limits
│   ├── safe_touchpoint.rb       # Read-only touchpoint wrapper
│   └── dsl_methods.rb           # within_window, apply, time_decay, normalize!
│
└── runtime/
    ├── timeout_handler.rb       # 5-second execution timeout
    ├── iteration_counter.rb     # 10,000 iteration limit
    └── credit_validator.rb      # Ensure credits sum to 1.0

test/services/aml/
├── parser_test.rb
├── validator_test.rb
├── executor_test.rb
├── compiler_test.rb
│
├── security/
│   ├── whitelist_test.rb
│   ├── ast_analyzer_test.rb
│   ├── command_injection_test.rb      # system, exec, backticks
│   ├── file_system_test.rb            # File, Dir, IO
│   ├── network_access_test.rb         # Net::HTTP, URI
│   ├── eval_metaprogramming_test.rb   # eval, send, define_method
│   ├── constant_manipulation_test.rb  # const_get, Object, Kernel
│   ├── global_variables_test.rb       # ENV, $LOAD_PATH
│   ├── resource_exhaustion_test.rb    # loops, memory, ReDoS
│   └── sandbox_escape_test.rb         # method chaining attacks
│
├── sandbox/
│   ├── context_test.rb
│   ├── safe_array_test.rb
│   ├── safe_touchpoint_test.rb
│   └── dsl_methods_test.rb
│
└── integration/
    ├── standard_models_test.rb        # All preset models as AML
    ├── custom_models_test.rb          # User-defined models
    └── edge_cases_test.rb             # 0, 1, 2 touchpoints
```

---

## Implementation Checklist

### Phase 0: Requirements Clarification
- [ ] **BLOCKER**: Get user input on stage/milestone definition for W-shaped
- [ ] Decide on stage storage (model config vs conversion property)
- [ ] Define stage matching semantics (exact vs closest)

### Phase 1: Foundation & Security Layer

#### 1.1 Project Setup
- [ ] Add `parser` gem to Gemfile
- [ ] Create `app/services/aml/` directory structure
- [ ] Create `test/services/aml/` directory structure
- [ ] Create `AML::Error` base exception class

#### 1.2 Security Whitelist (TDD)
- [ ] Define `ALLOWED_ARRAY_METHODS` constant
- [ ] Define `ALLOWED_STRING_METHODS` constant
- [ ] Define `ALLOWED_NUMERIC_METHODS` constant
- [ ] Define `ALLOWED_TIME_METHODS` constant
- [ ] Define `ALLOWED_HASH_METHODS` constant
- [ ] Define `ALLOWED_DSL_METHODS` constant
- [ ] Define `FORBIDDEN_METHODS` constant
- [ ] Define `FORBIDDEN_CONSTANTS` constant
- [ ] Write tests for each whitelist category
- [ ] Implement whitelist checker

#### 1.3 AST Analyzer Security Tests (RED Phase)
Write tests FIRST for each attack vector:

**Command Injection (10 tests)**
- [ ] `system("command")`
- [ ] `exec("command")`
- [ ] `spawn("command")`
- [ ] `` `command` `` (backticks)
- [ ] `%x{command}`
- [ ] `Kernel.system("command")`
- [ ] `IO.popen("command")`
- [ ] `Open3.capture2("command")`
- [ ] `PTY.spawn("command")`
- [ ] `Process.spawn("command")`

**File System Access (8 tests)**
- [ ] `File.read("/etc/passwd")`
- [ ] `File.open("/etc/passwd")`
- [ ] `File.write("/tmp/evil", "data")`
- [ ] `Dir.glob("/*")`
- [ ] `Dir.entries("/")`
- [ ] `IO.read("/etc/passwd")`
- [ ] `IO.readlines("/etc/passwd")`
- [ ] `FileUtils.rm_rf("/")`

**Network Access (6 tests)**
- [ ] `Net::HTTP.get("evil.com", "/")`
- [ ] `URI.open("http://evil.com")`
- [ ] `open("http://evil.com")`
- [ ] `require "net/http"`
- [ ] `require "open-uri"`
- [ ] `Socket.new(:INET, :STREAM)`

**Eval/Metaprogramming (12 tests)**
- [ ] `eval("code")`
- [ ] `instance_eval { }`
- [ ] `class_eval { }`
- [ ] `module_eval { }`
- [ ] `send(:system, "ls")`
- [ ] `__send__(:system, "ls")`
- [ ] `public_send(:system, "ls")`
- [ ] `define_method(:evil) { }`
- [ ] `undef_method(:to_s)`
- [ ] `remove_method(:to_s)`
- [ ] `method(:system).call("ls")`
- [ ] `method_missing` override attempt

**Constant Manipulation (8 tests)**
- [ ] `Object.const_get(:File)`
- [ ] `Object.const_set(:EVIL, "value")`
- [ ] `Module.const_get(:Kernel)`
- [ ] `::File.read("/etc/passwd")`
- [ ] `::Kernel.system("ls")`
- [ ] `Object::File`
- [ ] `self.class.const_get(:File)`
- [ ] `touchpoints.class.const_get(:File)`

**Global Variables (5 tests)**
- [ ] `ENV["API_KEY"]`
- [ ] `$LOAD_PATH`
- [ ] `$LOADED_FEATURES`
- [ ] `$0 = "evil"`
- [ ] `$SAFE` access

**Resource Exhaustion (8 tests)**
- [ ] Infinite `loop { }`
- [ ] Infinite `while true`
- [ ] `10_000_000.times { }`
- [ ] Memory bomb: `Array.new(10_000_000)`
- [ ] String bomb: `"a" * 10_000_000`
- [ ] ReDoS: `/^(a+)+$/` with long input
- [ ] Nested loops exhaustion
- [ ] `sleep(1000)` blocking

**Sandbox Escape (10+ tests)**
- [ ] `touchpoints.first.class.const_get(:File)`
- [ ] `"string".class.class.const_get(:File)`
- [ ] `1.class.superclass.const_get(:File)`
- [ ] `binding` access
- [ ] `caller` / `caller_locations`
- [ ] `__method__` / `__callee__`
- [ ] `ObjectSpace.each_object`
- [ ] `GC.start`
- [ ] `Thread.new { }`
- [ ] `Fiber.new { }`
- [ ] `Proc.new { }.binding`
- [ ] `lambda { }.binding`

#### 1.4 AST Analyzer Implementation (GREEN Phase)
- [ ] Implement `AML::Security::AstAnalyzer` class
- [ ] Implement recursive AST walker
- [ ] Detect `:send` nodes with forbidden methods
- [ ] Detect `:const` nodes with forbidden constants
- [ ] Detect `:xstr` nodes (backticks)
- [ ] Detect `:gvar` nodes (global variables)
- [ ] All security tests pass

---

### Phase 2: Parser & Validator

#### 2.1 Parser
- [ ] Create `AML::Parser` class
- [ ] Use `Parser::CurrentRuby.parse()` for parsing
- [ ] Handle syntax errors with line/column info
- [ ] Return structured AST representation
- [ ] Write parser tests

#### 2.2 Validator
- [ ] Create `AML::Validator` class
- [ ] Integrate security AST analyzer
- [ ] Validate `within_window` is present and first
- [ ] Validate credit assignments
- [ ] Validate duration values (1-365 days)
- [ ] Static credit sum validation where possible
- [ ] Collect all errors (don't fail fast)
- [ ] Write validator tests

---

### Phase 3: Sandbox & Execution

#### 3.1 Safe Wrappers
- [ ] Create `AML::Sandbox::SafeArray` with iteration limits
- [ ] Create `AML::Sandbox::SafeTouchpoint` (read-only)
- [ ] Create `AML::Sandbox::SafeTime` wrapper
- [ ] Write tests for each wrapper

#### 3.2 DSL Methods
- [ ] Implement `within_window(duration, &block)`
- [ ] Implement `apply(credit, to:, distribute:)`
- [ ] Implement `apply(to:, &block)` (block form)
- [ ] Implement `time_decay(half_life:)`
- [ ] Implement `normalize!`
- [ ] Write tests for each DSL method

#### 3.3 Execution Context
- [ ] Create `AML::Sandbox::Context < BasicObject`
- [ ] Expose only safe methods
- [ ] Block `method_missing` with SecurityError
- [ ] Block `respond_to?` for hidden methods
- [ ] Write context tests

#### 3.4 Executor
- [ ] Create `AML::Executor` class
- [ ] Integrate timeout (5 seconds)
- [ ] Track iteration count
- [ ] Execute within sandbox context
- [ ] Validate result credits sum to 1.0
- [ ] Handle execution errors gracefully
- [ ] Write executor tests

---

### Phase 4: Integration

#### 4.1 Standard Models as AML
- [ ] First Touch AML definition
- [ ] Last Touch AML definition
- [ ] Linear AML definition
- [ ] Time Decay AML definition
- [ ] U-Shaped AML definition
- [ ] W-Shaped AML definition (requires stage resolution - see Phase 0)
- [ ] Participation AML definition
- [ ] Write integration tests for each

#### 4.2 Database Migration
- [ ] Add `dsl_code` (text) column
- [ ] Add `compiled_ast` (jsonb) column
- [ ] Add `last_compiled_at` (datetime) column
- [ ] Add `compilation_error` (text) column
- [ ] Add `stage_events` (jsonb) column (if needed for W-shaped)
- [ ] Run migration

#### 4.3 Model Integration
- [ ] Update `AttributionModel` with AML methods
- [ ] Add `compile!` method
- [ ] Add `execute(touchpoints, conversion)` method
- [ ] Add validation callback for AML syntax
- [ ] Update `AlgorithmMapping` concern
- [ ] Write model tests

---

### Phase 5: Edge Cases & Hardening

#### 5.1 Edge Case Handling
- [ ] 0 touchpoints → empty result
- [ ] 1 touchpoint → 100% credit
- [ ] 2 touchpoints → handle U-shaped/W-shaped
- [ ] Division by zero protection
- [ ] Empty filter results
- [ ] Write edge case tests

#### 5.2 Error Handling
- [ ] Graceful syntax error messages
- [ ] Graceful security violation messages
- [ ] Graceful execution timeout handling
- [ ] Fallback to Last Touch on error
- [ ] Error logging for debugging
- [ ] Write error handling tests

#### 5.3 Performance
- [ ] Benchmark execution time
- [ ] Optimize hot paths
- [ ] Consider caching compiled AST
- [ ] Profile memory usage

---

## Security Whitelist Reference

### Allowed Methods by Type

```ruby
module AML
  module Security
    class Whitelist
      ALLOWED_ARRAY_METHODS = %w[
        [] length size count empty? any? all? none?
        first last
        select reject find find_all find_index
        map collect
        each each_with_index
        include?
        - + &
        slice
        sum
        min max minmax
        sort sort_by
        reverse
        take drop
        compact
        uniq
        flatten
        zip
      ].freeze

      ALLOWED_STRING_METHODS = %w[
        == != =~
        start_with? starts_with?
        end_with? ends_with?
        include?
        match?
        upcase downcase capitalize
        strip lstrip rstrip
        length size
        empty?
        split
        gsub sub
        [] slice
        to_s to_sym
      ].freeze

      ALLOWED_NUMERIC_METHODS = %w[
        + - * / ** %
        > < >= <= == != <=>
        abs floor ceil round truncate
        to_i to_f to_s
        between?
        positive? negative? zero?
        even? odd?
        divmod
        fdiv
      ].freeze

      ALLOWED_TIME_METHODS = %w[
        > < >= <= == != <=> between?
        + -
        year month day hour min sec wday yday
        monday? tuesday? wednesday? thursday? friday? saturday? sunday?
        beginning_of_day end_of_day
        beginning_of_week end_of_week
        beginning_of_month end_of_month
        to_i to_f to_s to_date to_datetime
        iso8601
        strftime
      ].freeze

      ALLOWED_DURATION_METHODS = %w[
        day days
        week weeks
        month months
        year years
        hour hours
        minute minutes
        second seconds
        ago from_now since until
        to_i to_f
        + - * /
      ].freeze

      ALLOWED_HASH_METHODS = %w[
        [] fetch
        key? has_key? include? member?
        keys values
        empty? any?
        length size count
        dig
        slice
        to_a
      ].freeze

      ALLOWED_MATH_METHODS = %w[
        exp log log10 log2
        sqrt cbrt
        sin cos tan
        asin acos atan atan2
        sinh cosh tanh
        asinh acosh atanh
        hypot
        erf erfc
        gamma lgamma
      ].freeze

      ALLOWED_DSL_METHODS = %w[
        within_window
        apply
        time_decay
        normalize!
        touchpoints
        conversion_time
        conversion_value
        stages
        stage
      ].freeze

      FORBIDDEN_METHODS = %w[
        eval instance_eval class_eval module_eval
        exec system spawn fork
        ` send __send__ public_send
        method_missing respond_to_missing?
        define_method define_singleton_method
        undef_method remove_method
        alias_method
        const_get const_set const_missing const_defined?
        remove_const
        class_variable_get class_variable_set
        instance_variable_get instance_variable_set
        extend include prepend
        require require_relative load autoload
        open
        binding
        caller caller_locations
        exit exit! abort
        raise fail throw catch
        sleep
        at_exit
        trap
        set_trace_func
        method __method__ __callee__
        singleton_class
        freeze frozen?
        taint untaint tainted?
        trust untrust untrusted?
        object_id __id__
      ].freeze

      FORBIDDEN_CONSTANTS = %w[
        File Dir IO FileUtils Pathname Tempfile
        Socket TCPSocket UDPSocket UNIXSocket
        Net HTTP HTTPS URI OpenURI
        Process Kernel Object Module Class
        Thread Fiber Mutex ConditionVariable Queue SizedQueue
        ObjectSpace GC
        Proc Method UnboundMethod
        Binding
        ENV ARGV ARGF
        DATA STDIN STDOUT STDERR
        Marshal YAML JSON
        Gem Bundler
        Rails ActiveRecord ActiveSupport
        DRb
        Ripper Parser
        RubyVM
        TracePoint
      ].freeze

      FORBIDDEN_GLOBALS = %w[
        $0 $PROGRAM_NAME
        $: $LOAD_PATH
        $" $LOADED_FEATURES
        $; $-F $FS $FIELD_SEPARATOR
        $, $OFS $OUTPUT_FIELD_SEPARATOR
        $/ $-0 $RS $INPUT_RECORD_SEPARATOR
        $\\ $ORS $OUTPUT_RECORD_SEPARATOR
        $. $NR $INPUT_LINE_NUMBER
        $_ $LAST_READ_LINE
        $> $DEFAULT_OUTPUT
        $< $DEFAULT_INPUT
        $$ $PID $PROCESS_ID
        $? $CHILD_STATUS
        $! $ERROR_INFO
        $@ $ERROR_POSITION
        $~ $MATCH
        $& $MATCH
        $` $PREMATCH
        $' $POSTMATCH
        $+ $LAST_PAREN_MATCH
        $= $IGNORECASE
        $* $ARGV
        $$ $SAFE
        $-d $DEBUG
        $-v $VERBOSE
        $-w $-W
        $stderr $stdout $stdin
      ].freeze
    end
  end
end
```

---

## Test Helpers

```ruby
# test/services/aml/security_test_helper.rb
module AML
  module SecurityTestHelper
    def assert_forbidden(code, message = nil)
      full_code = <<~AML
        within_window 30.days
          #{code}
          apply 1.0 to touchpoints[0]
        end
      AML

      error = assert_raises(AML::SecurityError) do
        AML::Validator.new(full_code).validate!
      end

      assert_match(/forbidden|not allowed|blocked/i, error.message, message)
    end

    def assert_allowed(code)
      full_code = <<~AML
        within_window 30.days
          #{code}
          apply 1.0 to touchpoints[0]
        end
      AML

      assert_nothing_raised do
        AML::Validator.new(full_code).validate!
      end
    end

    def assert_execution_error(code, error_class = AML::ExecutionError)
      assert_raises(error_class) do
        AML::Executor.new(code, context).call
      end
    end

    def build_context(touchpoint_count: 4)
      touchpoints = (0...touchpoint_count).map do |i|
        {
          session_id: i + 1,
          channel: "channel_#{i}",
          occurred_at: (touchpoint_count - i).days.ago
        }
      end

      AML::Sandbox::Context.new(
        touchpoints: touchpoints,
        conversion_time: Time.current,
        conversion_value: 100.0
      )
    end
  end
end
```

---

## Standard Model AML Definitions

```ruby
module AML
  module StandardModels
    FIRST_TOUCH = <<~AML
      within_window 30.days
        apply 1.0 to touchpoints[0]
      end
    AML

    LAST_TOUCH = <<~AML
      within_window 30.days
        apply 1.0 to touchpoints[-1]
      end
    AML

    LINEAR = <<~AML
      within_window 30.days
        apply 1.0 / touchpoints.length to touchpoints
      end
    AML

    TIME_DECAY = <<~AML
      within_window 30.days
        time_decay half_life: 7.days
      end
    AML

    U_SHAPED = <<~AML
      within_window 30.days
        case touchpoints.length
        when 0
          # No touchpoints
        when 1
          apply 1.0 to touchpoints[0]
        when 2
          apply 0.5 to touchpoints[0]
          apply 0.5 to touchpoints[-1]
        else
          apply 0.4 to touchpoints[0]
          apply 0.4 to touchpoints[-1]
          apply 0.2 to touchpoints[1..-2], distribute: :equal
        end
      end
    AML

    # W-Shaped requires stage configuration - see Open Questions
    # This is a placeholder that will need stage resolution
    W_SHAPED = <<~AML
      within_window 30.days
        # W-Shaped: First, Key Milestone(s), Last
        # Requires: stages array to be configured on the model
        #
        # Example with stages = ["mql_conversion", "sql_conversion"]:
        #   First touch: 22.5%
        #   MQL event:   22.5%
        #   SQL event:   22.5%
        #   Last touch:  22.5%
        #   Others:      10% (distributed equally)

        case touchpoints.length
        when 0
          # No touchpoints
        when 1
          apply 1.0 to touchpoints[0]
        when 2
          apply 0.5 to touchpoints[0]
          apply 0.5 to touchpoints[-1]
        else
          # Placeholder - actual implementation depends on stage resolution
          key_positions = 2 + stages.length  # first + stages + last
          key_credit = 0.9 / key_positions

          apply key_credit to touchpoints[0]
          apply key_credit to touchpoints[-1]

          stages.each do |stage_event|
            stage_tp = touchpoints.find { |tp| tp.event_type == stage_event }
            apply key_credit to stage_tp if stage_tp
          end

          # Remaining 10% to others
          others = touchpoints.reject { |tp|
            tp == touchpoints[0] ||
            tp == touchpoints[-1] ||
            stages.include?(tp.event_type)
          }
          apply 0.1 to others, distribute: :equal if others.any?

          normalize!
        end
      end
    AML

    PARTICIPATION = <<~AML
      within_window 30.days
        # Participation doesn't normalize to 1.0
        # Each unique channel gets 1.0 credit
        apply 1.0 to touchpoints, distribute: :equal, normalize: false
      end
    AML
  end
end
```

---

## Success Criteria

### Security
- [ ] All 50+ security tests pass
- [ ] No sandbox escapes possible
- [ ] All attack vectors from `aml_security_spec.md` blocked
- [ ] External security review (optional)

### Functionality
- [ ] All 7 preset models execute correctly via AML
- [ ] Custom models can be defined and executed
- [ ] Edge cases (0, 1, 2 touchpoints) handled
- [ ] Credits always sum to 1.0 (or validate error)

### Performance
- [ ] Execution < 100ms for typical models
- [ ] Timeout enforced at 5 seconds
- [ ] Memory usage bounded

### Developer Experience
- [ ] Clear error messages with line/column info
- [ ] Helpful validation suggestions
- [ ] Comprehensive test coverage (95%+)

---

## References

- [aml_security_spec.md](./aml_security_spec.md) - Security requirements
- [attribution_dsl_design.md](./attribution_dsl_design.md) - DSL syntax design
- [attribution_dsl_plan.md](./attribution_dsl_plan.md) - AST node design
- [Parser gem AST format](https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md)
- [Ruby Security Docs](https://docs.ruby-lang.org/en/2.3.0/security_rdoc.html)
