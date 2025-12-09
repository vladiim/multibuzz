# AML Security Specification

**INTERNAL DOCUMENT - DO NOT SHARE EXTERNALLY**

**Version**: 1.0
**Status**: Design Phase
**Last Updated**: 2025-12-07

---

## Overview

Attribution Modeling Language (AML) allows users to write Ruby-like code for custom attribution models. Since user-provided code will be executed on our servers, we must implement **defense-in-depth security** to prevent:

- Arbitrary code execution
- File system access
- Network access
- Database manipulation
- Resource exhaustion (DOS)
- Data exfiltration
- Privilege escalation

---

## Security Architecture

### Layers of Defense

```
┌─────────────────────────────────────────┐
│ Layer 1: Input Validation              │  ← Reject malformed syntax
├─────────────────────────────────────────┤
│ Layer 2: AST Analysis                  │  ← Detect forbidden operations
├─────────────────────────────────────────┤
│ Layer 3: Whitelist Enforcement         │  ← Allow only safe methods
├─────────────────────────────────────────┤
│ Layer 4: Sandboxed Execution           │  ← Isolated Ruby environment
├─────────────────────────────────────────┤
│ Layer 5: Resource Limits               │  ← Timeout, memory, CPU caps
├─────────────────────────────────────────┤
│ Layer 6: Audit Logging                 │  ← Track all executions
└─────────────────────────────────────────┘
```

**Principle**: Multiple independent layers. If one fails, others still protect.

---

## Layer 1: Input Validation

### Syntax Validation

Parse AML code using Ruby's built-in parser (`Ripper` or `Parser` gem):

```ruby
class AML::Validator
  def validate_syntax(code)
    Ripper.sexp(code)
  rescue SyntaxError => e
    raise AML::ValidationError, "Syntax error: #{e.message}"
  end
end
```

**Reject**:
- Invalid Ruby syntax
- Code > 10,000 characters
- More than 100 lines
- Non-UTF-8 encoding

---

## Layer 2: AST Analysis

### Forbidden Operations Detection

Walk the AST and detect dangerous operations:

```ruby
class AML::ASTAnalyzer
  FORBIDDEN_METHODS = %w[
    eval instance_eval class_eval module_eval
    send __send__ public_send method_missing
    define_method undef_method remove_method
    const_get const_set const_missing
    require require_relative load
    system exec spawn fork
    exit exit! abort
    raise fail throw
    open File.open Dir.open IO.open
    File Dir IO Kernel Process
    Net::HTTP URI.open open-uri
    ENV $LOAD_PATH $: $SAFE
    ` %x
  ].freeze

  FORBIDDEN_CONSTANTS = %w[
    File Dir IO Kernel Process
    Net HTTP URI
    Thread Mutex
    ObjectSpace GC
  ].freeze

  def analyze(sexp)
    walk_tree(sexp) do |node|
      case node[0]
      when :call, :fcall
        method_name = node[2]
        raise_if_forbidden_method(method_name)

      when :const, :const_path_ref
        const_name = extract_constant_name(node)
        raise_if_forbidden_constant(const_name)

      when :xstring
        raise AML::ValidationError, "Backtick command execution not allowed"

      when :dyna_symbol
        raise AML::ValidationError, "Dynamic symbols not allowed (security risk)"
      end
    end
  end

  private

  def raise_if_forbidden_method(method_name)
    if FORBIDDEN_METHODS.include?(method_name.to_s)
      raise AML::ValidationError, "Forbidden method: #{method_name}"
    end
  end

  def raise_if_forbidden_constant(const_name)
    if FORBIDDEN_CONSTANTS.include?(const_name)
      raise AML::ValidationError, "Forbidden constant: #{const_name}"
    end
  end
end
```

**Detect and reject**:
- Backticks (`` `ls` ``)
- `%x{command}`
- `system()`, `exec()`, `spawn()`
- `eval()`, `instance_eval()`, `class_eval()`
- `send()`, `__send__()`, `public_send()`
- `require()`, `require_relative()`, `load()`
- File/IO operations
- Network operations
- Dangerous constants

---

## Layer 3: Whitelist Enforcement

### Allowed Methods Whitelist

Only these methods are permitted:

#### Array Methods
```ruby
ALLOWED_ARRAY_METHODS = %w[
  [] []=
  length size count empty? any?
  first last
  select reject find find_all
  map collect
  each each_with_index
  - + &
  slice
  include?
].freeze
```

#### String Methods
```ruby
ALLOWED_STRING_METHODS = %w[
  == != =~ !~
  starts_with? start_with?
  ends_with? end_with?
  include?
  match?
  upcase downcase
  strip
  length size
].freeze
```

#### Numeric Methods
```ruby
ALLOWED_NUMERIC_METHODS = %w[
  + - * / ** %
  > < >= <= == !=
  abs floor ceil round
  to_i to_f to_s
  between?
].freeze
```

#### Time Methods
```ruby
ALLOWED_TIME_METHODS = %w[
  > < >= <= == != between?
  - +
  hour day wday month year
  saturday? sunday? monday? tuesday? wednesday? thursday? friday?
  beginning_of_day end_of_day
  to_i to_f
].freeze
```

#### Duration Methods (ActiveSupport)
```ruby
ALLOWED_DURATION_METHODS = %w[
  day days
  week weeks
  month months
  year years
  hour hours
  minute minutes
  ago from_now
  to_i
].freeze
```

#### Math Methods
```ruby
ALLOWED_MATH_METHODS = %w[
  exp log log10 log2
  sqrt cbrt
  sin cos tan
  asin acos atan
].freeze
```

#### Hash Methods (for touchpoint.properties)
```ruby
ALLOWED_HASH_METHODS = %w[
  [] []=
  key? has_key? include?
  keys values
  empty?
  fetch
].freeze
```

#### AML DSL Methods
```ruby
ALLOWED_DSL_METHODS = %w[
  time_decay
  normalize!
  apply
  within_window
].freeze
```

### Method Call Interceptor

Intercept all method calls and validate against whitelist:

```ruby
class AML::SafeContext
  def method_missing(method_name, *args, &block)
    # Check if method is whitelisted for this object type
    unless whitelisted?(method_name, self)
      raise AML::SecurityError, "Method not allowed: #{method_name}"
    end

    super
  end

  private

  def whitelisted?(method_name, object)
    case object
    when Array
      ALLOWED_ARRAY_METHODS.include?(method_name.to_s)
    when String
      ALLOWED_STRING_METHODS.include?(method_name.to_s)
    when Numeric
      ALLOWED_NUMERIC_METHODS.include?(method_name.to_s)
    when Time, ActiveSupport::TimeWithZone
      ALLOWED_TIME_METHODS.include?(method_name.to_s)
    when ActiveSupport::Duration
      ALLOWED_DURATION_METHODS.include?(method_name.to_s)
    else
      false
    end
  end
end
```

---

## Layer 4: Sandboxed Execution

### Implementation Options

#### Option A: Safe Ruby Subprocess (Recommended)

Run AQL in a separate Ruby subprocess with restricted permissions:

```ruby
class AML::Executor
  def execute(code, context)
    # Serialize context (touchpoints, conversion_time, etc.)
    serialized_context = Marshal.dump(context)

    # Spawn subprocess with timeout
    result = Timeout.timeout(5.seconds) do
      IO.popen(
        ["ruby", "--disable-gems", "-"],
        "r+",
        err: [:child, :out]
      ) do |io|
        io.write(sandbox_wrapper(code, serialized_context))
        io.close_write
        io.read
      end
    end

    # Deserialize result
    Marshal.load(result)
  rescue Timeout::Error
    raise AML::ExecutionError, "Execution timeout (5 seconds)"
  rescue => e
    raise AML::ExecutionError, "Execution failed: #{e.message}"
  end

  private

  def sandbox_wrapper(code, serialized_context)
    <<~RUBY
      # Disable dangerous features
      $SAFE = 1  # Taint checking (if Ruby < 3.0)

      # Undefine dangerous methods
      Object.class_eval do
        undef_method :system if method_defined?(:system)
        undef_method :exec if method_defined?(:exec)
        undef_method :` if method_defined?(:`)
      end

      # Load context
      context = Marshal.load(STDIN.read(#{serialized_context.bytesize}))

      # Execute AQL code
      result = eval(<<~AQL_CODE)
        #{code}
      AQL_CODE

      # Return result
      puts Marshal.dump(result)
    RUBY
  end
end
```

**Security Benefits**:
- Separate process = OS-level isolation
- Can use `ulimit` to restrict resources
- Can run in Docker container for additional isolation
- Process death doesn't affect main app

**Drawbacks**:
- Slower (process spawn overhead)
- Complexity in serialization

---

#### Option B: Sandboxed Binding (Faster, Less Secure)

Use a restricted binding with custom BasicObject:

```ruby
class AML::SafeBinding < BasicObject
  def initialize(touchpoints:, conversion_time:, conversion_value:)
    @touchpoints = touchpoints
    @conversion_time = conversion_time
    @conversion_value = conversion_value
    @credits = ::Array.new(touchpoints.length, 0.0)
  end

  def touchpoints
    @touchpoints
  end

  def conversion_time
    @conversion_time
  end

  def conversion_value
    @conversion_value
  end

  def apply(credit, to: nil, distribute: nil, &block)
    # Implementation
  end

  def normalize!
    # Implementation
  end

  # Block any other method calls
  def method_missing(method_name, *args, &block)
    ::Kernel.raise ::AML::SecurityError, "Method not allowed: #{method_name}"
  end
end

class AML::Executor
  def execute(code, context)
    binding = AML::SafeBinding.new(
      touchpoints: context.touchpoints,
      conversion_time: context.conversion_time,
      conversion_value: context.conversion_value
    )

    Timeout.timeout(5.seconds) do
      binding.instance_eval(code)
    end

    binding.credits
  rescue Timeout::Error
    raise AML::ExecutionError, "Execution timeout"
  end
end
```

**Security Benefits**:
- Faster (no process spawn)
- Simpler implementation

**Drawbacks**:
- Less isolated (same Ruby process)
- Harder to enforce all restrictions
- Risk of sandbox escape

**Recommendation**: Start with **Option B for MVP**, migrate to **Option A for production**.

---

## Layer 5: Resource Limits

### Timeout

**Hard limit**: 5 seconds per execution

```ruby
Timeout.timeout(5.seconds) do
  execute_aql(code)
end
```

If exceeded:
- Execution terminated
- Error logged
- Fallback to Last Touch attribution

---

### Memory Limit

**Limit**: 50 MB per execution

```ruby
# In subprocess (Option A)
ulimit -v 51200  # 50 MB in KB

# In-process (Option B) - harder to enforce
# Monitor via ObjectSpace or GC stats
```

---

### CPU Limit

**Limit**: 3 seconds of CPU time

```ruby
# In subprocess (Option A)
ulimit -t 3  # 3 CPU seconds

# In-process (Option B)
# Monitor via Process.times
```

---

### Iteration Limit

**Limit**: 10,000 loop iterations

Prevent infinite loops:

```ruby
class AML::SafeArray < Array
  MAX_ITERATIONS = 10_000

  def each(&block)
    iteration_count = 0
    super do |item|
      iteration_count += 1
      if iteration_count > MAX_ITERATIONS
        raise AML::ExecutionError, "Iteration limit exceeded (10,000)"
      end
      block.call(item)
    end
  end

  # Same for: select, reject, map, each_with_index, etc.
end
```

---

## Layer 6: Audit Logging

### Log All Executions

```ruby
class AML::Executor
  def execute(code, context)
    execution_id = SecureRandom.uuid
    start_time = Time.current

    Rails.logger.tagged("AQL", execution_id) do
      Rails.logger.info("Starting execution", {
        account_id: context.account_id,
        model_id: context.model_id,
        touchpoint_count: context.touchpoints.length
      })

      result = execute_sandboxed(code, context)

      Rails.logger.info("Execution successful", {
        duration_ms: ((Time.current - start_time) * 1000).round(2),
        credits: result
      })

      result
    end
  rescue => e
    Rails.logger.error("Execution failed", {
      error: e.class.name,
      message: e.message,
      backtrace: e.backtrace.first(5)
    })
    raise
  end
end
```

### Store Execution Metadata

```ruby
# Table: attribution_model_executions
create_table :attribution_model_executions do |t|
  t.references :account, null: false
  t.references :attribution_model, null: false
  t.references :conversion, null: false
  t.integer :touchpoint_count
  t.decimal :execution_time_ms, precision: 10, scale: 2
  t.string :status  # success, error, timeout
  t.text :error_message
  t.timestamps
end
```

**Use cases**:
- Detect abuse (repeatedly failing models)
- Performance monitoring
- Security audit trail
- Debug customer issues

---

## Validation Requirements

### Pre-Execution Validation

Before executing ANY AQL code:

1. ✅ **Syntax check** - Valid Ruby syntax?
2. ✅ **AST analysis** - No forbidden operations?
3. ✅ **Whitelist check** - Only allowed methods?
4. ✅ **Structure check** - Has `within_window`?
5. ✅ **Credit sum check** - Adds to 1.0 or uses `normalize!`?
6. ✅ **Size check** - Under 10,000 chars?

**If any check fails: REJECT immediately. Do not execute.**

---

### Runtime Validation

During execution:

1. ✅ **Timeout check** - Execution time < 5s?
2. ✅ **Memory check** - Memory usage < 50 MB?
3. ✅ **Iteration check** - Loop iterations < 10,000?
4. ✅ **Method check** - All method calls whitelisted?

**If any check fails: TERMINATE immediately.**

---

### Post-Execution Validation

After execution completes:

1. ✅ **Credit sum check** - Credits sum to 1.0 ± 0.0001?
2. ✅ **Credit range check** - All credits between 0.0 and 1.0?
3. ✅ **Array size check** - Credits array matches touchpoints array?

**If any check fails: REJECT result, use fallback.**

---

## Security Testing Requirements

### Unit Tests

Test each security layer independently:

```ruby
# Test forbidden method detection
test "rejects eval" do
  code = <<~AQL
    within_window 30.days
      eval("malicious code")
      apply 1.0 to touchpoints[0]
    end
  AQL

  assert_raises(AML::ValidationError) do
    AML::Validator.new.validate(code)
  end
end

# Test timeout
test "times out after 5 seconds" do
  code = <<~AQL
    within_window 30.days
      loop { }  # Infinite loop
    end
  AQL

  assert_raises(AML::ExecutionError) do
    AML::Executor.new.execute(code, context)
  end
end
```

---

### Integration Tests

Test full execution flow:

```ruby
test "executes safe U-shaped model" do
  code = <<~AQL
    within_window 30.days
      apply 0.4 to touchpoints[0]
      apply 0.4 to touchpoints[-1]
      apply 0.2 to touchpoints[1..-2], distribute: :equal
    end
  AQL

  context = build_context(touchpoints: 4)
  credits = AML::Executor.new.execute(code, context)

  assert_equal [0.4, 0.1, 0.1, 0.4], credits
  assert_in_delta 1.0, credits.sum, 0.0001
end
```

---

### Security Tests (Penetration Testing)

Attempt to break sandbox:

```ruby
# Attempt 1: File system access
test "blocks file system access" do
  code = <<~AQL
    within_window 30.days
      File.read("/etc/passwd")
    end
  AQL

  assert_raises(AML::ValidationError) { execute(code) }
end

# Attempt 2: Network access
test "blocks network access" do
  code = <<~AQL
    within_window 30.days
      require 'net/http'
      Net::HTTP.get('evil.com', '/')
    end
  AQL

  assert_raises(AML::ValidationError) { execute(code) }
end

# Attempt 3: Command injection via backticks
test "blocks backtick commands" do
  code = <<~AQL
    within_window 30.days
      `rm -rf /`
    end
  AQL

  assert_raises(AML::ValidationError) { execute(code) }
end

# Attempt 4: Constant manipulation
test "blocks const_set" do
  code = <<~AQL
    within_window 30.days
      Object.const_set(:API_KEY, "hacked")
    end
  AQL

  assert_raises(AML::ValidationError) { execute(code) }
end

# Attempt 5: Method injection
test "blocks define_method" do
  code = <<~AQL
    within_window 30.days
      define_method(:evil) { system("ls") }
    end
  AQL

  assert_raises(AML::ValidationError) { execute(code) }
end

# Attempt 6: Send to bypass restrictions
test "blocks send" do
  code = <<~AQL
    within_window 30.days
      touchpoints.send(:system, "ls")
    end
  AQL

  assert_raises(AML::ValidationError) { execute(code) }
end

# Attempt 7: Global variable manipulation
test "blocks ENV access" do
  code = <<~AQL
    within_window 30.days
      ENV['API_KEY']
    end
  AQL

  assert_raises(AML::ValidationError) { execute(code) }
end

# Attempt 8: Object space manipulation
test "blocks ObjectSpace" do
  code = <<~AQL
    within_window 30.days
      ObjectSpace.each_object(ApiKey) { |key| puts key.key }
    end
  AQL

  assert_raises(AML::ValidationError) { execute(code) }
end
```

**Requirement**: All penetration tests MUST fail (i.e., sandbox prevents attack).

---

## Known Attack Vectors

### 1. Sandbox Escape via Method Chaining

**Attack**:
```ruby
touchpoints.first.class.const_get(:File).read("/etc/passwd")
```

**Defense**: Whitelist only safe methods. Block `.class`, `.const_get`, etc.

---

### 2. Resource Exhaustion (DOS)

**Attack**:
```ruby
within_window 30.days
  1_000_000.times { |i| touchpoints.select { |tp| tp.channel == "paid_#{i}" } }
end
```

**Defense**: Iteration limit (10,000), timeout (5s).

---

### 3. Data Exfiltration via Timing

**Attack**:
```ruby
# Leak data via execution time
within_window 30.days
  if api_key_exists_in_database?
    sleep(5)  # Signal "true"
  else
    sleep(0)  # Signal "false"
  end
end
```

**Defense**:
- No database access in sandbox
- Block `sleep`, `Kernel.sleep`
- Constant-time execution for errors

---

### 4. Regex DOS (ReDoS)

**Attack**:
```ruby
within_window 30.days
  touchpoints.select { |tp| tp.channel.match?(/^(a+)+$/) }  # O(2^n) complexity
end
```

**Defense**:
- Timeout (5s) catches slow regex
- Limit regex complexity (AST analysis)
- Consider using `re2` gem for safe regex

---

### 5. Memory Bomb

**Attack**:
```ruby
within_window 30.days
  huge_array = Array.new(10_000_000, "a" * 10_000)
end
```

**Defense**:
- Memory limit (50 MB)
- Timeout catches slow allocation

---

## Deployment Considerations

### Production Hardening

1. **Run in Docker container** with:
   - Read-only filesystem
   - No network access
   - Limited CPU/memory via cgroups
   - Seccomp profile (block dangerous syscalls)

2. **Use separate process** (Option A):
   - Better isolation
   - Can kill without affecting main app
   - Use `ulimit` for resource restrictions

3. **Monitor execution metrics**:
   - Track execution times
   - Alert on repeated failures
   - Auto-disable models that error > 10 times

4. **Rate limit model execution**:
   - Max 1,000 executions/hour per account
   - Prevents abuse

---

### Security Monitoring

**Metrics to track**:
- Execution failures per model
- Timeout rate
- Average execution time
- Validation rejection rate
- Accounts with > 10 failed models

**Alerts**:
- Model execution time > 3s (warning)
- Model execution time > 4.5s (critical)
- Validation rejection rate > 50%
- Repeated timeouts from same account

---

## Incident Response Plan

### Scenario: Sandbox Escape Detected

1. **Immediate**:
   - Disable all custom models globally
   - Switch all accounts to preset models
   - Page security team

2. **Investigation** (< 1 hour):
   - Identify exploit vector
   - Determine blast radius (affected accounts)
   - Preserve logs and evidence

3. **Mitigation** (< 4 hours):
   - Patch sandbox vulnerability
   - Deploy fix to production
   - Re-enable custom models with enhanced validation

4. **Post-Mortem** (< 1 week):
   - Root cause analysis
   - Update security tests
   - Customer communication (if data exposed)

---

## Open Questions

1. **Should we support custom Ruby gems in the future?**
   - Pros: More power, community gems
   - Cons: Security risk, dependency hell
   - **Decision**: No custom gems. Too risky.

2. **Should we allow database queries (read-only)?**
   - Pros: More powerful models (e.g., "attribute based on user segment")
   - Cons: Performance, security, complexity
   - **Decision**: No direct DB access. Provide pre-computed context instead.

3. **Should we expose account-level settings in AQL?**
   - Example: `account.timezone`, `account.currency`
   - Pros: More flexible models
   - Cons: Information leakage risk
   - **Decision**: TBD. If yes, whitelist specific fields only.

4. **Should we allow models to call other models?**
   - Example: "Use Linear for journeys < 3 touchpoints, else use custom logic"
   - Pros: Composability
   - Cons: Recursion risk, complexity
   - **Decision**: TBD. If yes, limit recursion depth to 2.

---

## Implementation Checklist

### Phase 1: Parser & Validator
- [ ] Implement syntax validator (Ripper)
- [ ] Implement AST analyzer
- [ ] Build forbidden operation detector
- [ ] Create whitelist enforcer
- [ ] Write validation tests (100+ cases)

### Phase 2: Executor
- [ ] Implement safe execution environment
- [ ] Add timeout mechanism
- [ ] Add memory limits
- [ ] Add iteration limits
- [ ] Write execution tests

### Phase 3: Security Hardening
- [ ] Add audit logging
- [ ] Implement rate limiting
- [ ] Create security monitoring dashboard
- [ ] Write penetration tests (50+ attack vectors)
- [ ] External security audit

### Phase 4: Production Deployment
- [ ] Docker container with restricted permissions
- [ ] Seccomp profile
- [ ] Resource monitoring
- [ ] Incident response runbook

### Phase 5: Documentation
- [ ] User-facing API docs (done)
- [ ] Security whitepaper
- [ ] Developer implementation guide
- [ ] Security audit report

---

## References

- [Ruby $SAFE levels](https://ruby-doc.org/core-2.7.0/doc/security_rdoc.html)
- [OWASP Code Injection](https://owasp.org/www-community/attacks/Code_Injection)
- [Sandboxing Ruby](https://www.jstorimer.com/blogs/workingwithcode/7766107-5-ways-to-sandbox-ruby-code)
- [ReDoS Prevention](https://owasp.org/www-community/attacks/Regular_expression_Denial_of_Service_-_ReDoS)
- [Docker Security](https://docs.docker.com/engine/security/)

---

**This spec is a living document. Update as threats evolve and new attack vectors are discovered.**
