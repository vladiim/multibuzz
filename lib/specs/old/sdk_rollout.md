# SDK Rollout: Prioritization & Ruby SDK Translation Guide

## Part 1: SDK Prioritization

| Priority | SDK | ICP Coverage | Difficulty | Rationale |
|----------|-----|--------------|------------|-----------|
| **1** | Node.js | 95% | Low | Express middleware = Rack; 40.8% runtime usage; dominates modern SaaS |
| **2** | Python | 90% | Low-Med | WSGI mirrors Rack; #1 language (26% TIOBE); Django/Flask/FastAPI |
| **3** | Magento 2 | 85% | High | Enterprise e-commerce; 8-18% market; spec already exists |
| **4** | Shopify | 80% | High | 25-30% US market; webhook-based (different pattern); checkout deprecations |
| **5** | PHP | 75% | Medium | 73% of web (WordPress); no native middleware; fragmented frameworks |

### Key Insight
**Node.js first** - middleware pattern translates directly from Ruby/Rack. Same conceptual model, same flow.

---

## Part 2: Ruby SDK Complete Breakdown

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Mbuzz Module                             │
│  Public API: init(), event(), conversion(), identify()          │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ Configuration │    │ RequestContext│    │    Client     │
│   Singleton   │    │ Thread-local  │    │  Orchestrator │
└───────────────┘    └───────────────┘    └───────────────┘
                                                  │
        ┌──────────────┬──────────────┬──────────┴──────────┐
        ▼              ▼              ▼                     ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐   ┌─────────────┐
│TrackRequest │ │IdentRequest │ │ConvRequest  │   │SessRequest  │
└─────────────┘ └─────────────┘ └─────────────┘   └─────────────┘
        │              │              │                   │
        └──────────────┴──────────────┴───────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │      Api        │
                    │  HTTP Client    │
                    └─────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   Middleware::Tracking                          │
│  Rack middleware: cookies, context, session creation            │
└─────────────────────────────────────────────────────────────────┘
```

---

### Component 1: Configuration

**File:** `lib/mbuzz/configuration.rb`

**Purpose:** Store SDK settings as a singleton.

**Properties:**
```
api_key          : string  (required)
api_url          : string  (default: "https://mbuzz.co/api/v1")
enabled          : boolean (default: true)
debug            : boolean (default: false)
timeout          : integer (default: 5 seconds)
skip_paths       : array   (default: [])
skip_extensions  : array   (default: [])
```

**Default Skip Paths:**
```
/up, /health, /healthz, /ping, /cable, /assets, /packs, /rails/active_storage, /api
```

**Default Skip Extensions:**
```
.js, .css, .map, .png, .jpg, .jpeg, .gif, .ico, .svg, .woff, .woff2, .ttf, .eot, .webp
```

**Translation Notes:**
- Implement as singleton or module-level config object
- `all_skip_paths()` = DEFAULT_SKIP_PATHS + user-provided skip_paths
- `all_skip_extensions()` = DEFAULT_SKIP_EXTENSIONS + user-provided skip_extensions

---

### Component 2: HTTP Client (Api)

**File:** `lib/mbuzz/api.rb`

**Purpose:** Make authenticated HTTP POST requests to mbuzz API.

**Methods:**

```ruby
# Returns boolean - for fire-and-forget calls
Api.post(path, payload) → true/false

# Returns parsed JSON - for calls needing response data
Api.post_with_response(path, payload) → Hash/nil
```

**Request Construction:**
```
Method:  POST
URL:     {api_url}{path}  (e.g., https://mbuzz.co/api/v1/events)
Headers:
  Authorization: Bearer {api_key}
  Content-Type:  application/json
  User-Agent:    mbuzz-{language}/{version}
Body:    JSON.stringify(payload)
Timeout: 5 seconds (configurable)
SSL:     Verify peer certificate
```

**Response Handling:**
- Status 200-299 → success
- Any other status → log error if debug mode, return false/nil
- Catch network errors (timeout, connection refused) → return false/nil

**Critical Behavior:**
- **Never throw exceptions** - always return false/nil on failure
- Log errors only when `debug: true`
- Cache URI objects for performance (optional optimization)

**Translation Notes:**
- Use native HTTP library (no external dependencies if possible)
- Node: `fetch` or `https` module
- Python: `requests` or `urllib3`
- PHP: `curl` or Guzzle

---

### Component 3: Visitor Identifier

**File:** `lib/mbuzz/visitor/identifier.rb`

**Purpose:** Generate random visitor IDs.

**Implementation:**
```ruby
SecureRandom.hex(32)  # → 64-character hex string
```

**Translation:**
- Node: `crypto.randomBytes(32).toString('hex')`
- Python: `secrets.token_hex(32)`
- PHP: `bin2hex(random_bytes(32))`

---

### Component 4: Request Context (Thread-Local Storage)

**File:** `lib/mbuzz/request_context.rb`

**Purpose:** Store current request in thread-local storage so `Mbuzz.event()` can access URL/referrer without passing them explicitly.

**Pattern:**
```ruby
# Store request for duration of block
RequestContext.with_context(request: rack_request) do
  # Inside here, RequestContext.current returns the context
  yield
end
# After block, context is cleared

# Access current context
context = RequestContext.current  # → RequestContext instance or nil
context.url                       # → current request URL
context.referrer                  # → HTTP Referer header
context.enriched_properties({})   # → { url: "...", referrer: "..." }
```

**Key Method - enriched_properties:**
```ruby
def enriched_properties(custom = {})
  { url: url, referrer: referrer }.compact.merge(custom)
end
```

This auto-adds `url` and `referrer` to event properties.

**Translation:**
- Node: `AsyncLocalStorage` (Node 12.17+) or continuation-local-storage
- Python: `contextvars.ContextVar` (Python 3.7+)
- PHP: Store in `$_SERVER` superglobal or request attribute bag

---

### Component 5: Middleware

**File:** `lib/mbuzz/middleware/tracking.rb`

**Purpose:** Intercept every request to:
1. Generate/read visitor_id and session_id cookies
2. Store IDs in request env for access anywhere
3. Create session on first request
4. Set response cookies

**Request Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│                     Incoming Request                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    1. Skip Check                             │
│  if path in skip_paths OR extension in skip_extensions:      │
│      return app.call(env)  # Pass through, no tracking       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  2. Extract/Generate IDs                     │
│  visitor_id = cookie['_mbuzz_vid'] || generate_new()         │
│  session_id = cookie['_mbuzz_sid'] || generate_new()         │
│  user_id    = session['user_id']  (from app session)         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  3. Store in Request Env                     │
│  env['mbuzz.visitor_id'] = visitor_id                        │
│  env['mbuzz.session_id'] = session_id                        │
│  env['mbuzz.user_id']    = user_id                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│            4. Create Session (if new session_id)             │
│  if session_id was generated (not from cookie):              │
│      Thread.new { create_session_api_call() }                │
│  # Async so we don't block the request                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│             5. Set Request Context & Call App                │
│  RequestContext.with_context(request: request) do            │
│      status, headers, body = app.call(env)                   │
│  end                                                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   6. Set Response Cookies                    │
│  Set-Cookie: _mbuzz_vid={visitor_id}; Max-Age=63072000;      │
│              Path=/; HttpOnly; SameSite=Lax; [Secure]        │
│  Set-Cookie: _mbuzz_sid={session_id}; Max-Age=1800;          │
│              Path=/; HttpOnly; SameSite=Lax; [Secure]        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Return Response                           │
└─────────────────────────────────────────────────────────────┘
```

**Cookie Configuration:**

| Cookie | Name | Max-Age | Attributes |
|--------|------|---------|------------|
| Visitor | `_mbuzz_vid` | 2 years (63,072,000s) | HttpOnly, SameSite=Lax, Path=/, Secure (if HTTPS) |
| Session | `_mbuzz_sid` | 30 min (1,800s) | HttpOnly, SameSite=Lax, Path=/, Secure (if HTTPS) |

**Translation Notes:**
- Node/Express: `app.use((req, res, next) => { ... })`
- Python/Django: Middleware class with `__call__`
- Python/Flask: `@app.before_request` and `@app.after_request`
- PHP/Laravel: Middleware class with `handle()` method

---

### Component 6: Request Classes

#### 6a. TrackRequest (Events)

**File:** `lib/mbuzz/client/track_request.rb`

**Endpoint:** `POST /events`

**Payload:**
```json
{
  "events": [{
    "user_id": "user_123",           // optional
    "visitor_id": "abc123...",       // required if no user_id
    "session_id": "xyz789...",       // optional
    "event_type": "page_view",       // required
    "properties": {                  // required (can be empty {})
      "url": "https://...",
      "referrer": "https://...",
      "custom_key": "value"
    },
    "timestamp": "2025-12-15T10:30:00Z"  // ISO8601 UTC
  }]
}
```

**Validation:**
- `event_type` must be present (non-empty string)
- `properties` must be a hash/object
- Must have either `user_id` OR `visitor_id`

**Response:**
```json
{
  "events": [{
    "id": "evt_abc123",
    "event_type": "page_view",
    "visitor_id": "abc123...",
    "session_id": "xyz789..."
  }]
}
```

**Return Value:**
```ruby
{ success: true, event_id: "evt_abc123", event_type: "page_view",
  visitor_id: "abc123...", session_id: "xyz789..." }
# OR
false  # on any failure
```

---

#### 6b. ConversionRequest

**File:** `lib/mbuzz/client/conversion_request.rb`

**Endpoint:** `POST /conversions`

**Payload:**
```json
{
  "conversion": {
    "conversion_type": "purchase",           // required
    "revenue": 99.99,                        // optional
    "currency": "USD",                       // default: "USD"
    "visitor_id": "abc123...",               // at least one identifier
    "user_id": "user_123",                   // at least one identifier
    "event_id": "evt_abc123",                // at least one identifier
    "is_acquisition": false,                 // optional, default false
    "inherit_acquisition": false,            // optional, default false
    "properties": {},                        // required (can be empty)
    "timestamp": "2025-12-15T10:30:00Z"
  }
}
```

**Validation:**
- `conversion_type` must be present
- `properties` must be a hash/object
- Must have at least ONE of: `event_id`, `visitor_id`, `user_id`

**Response:**
```json
{
  "conversion": { "id": "conv_abc123" },
  "attribution": { ... }
}
```

**Return Value:**
```ruby
{ success: true, conversion_id: "conv_abc123", attribution: { ... } }
# OR
false
```

---

#### 6c. IdentifyRequest

**File:** `lib/mbuzz/client/identify_request.rb`

**Endpoint:** `POST /identify`

**Payload:**
```json
{
  "user_id": "user_123",           // required (string or numeric)
  "visitor_id": "abc123...",       // optional
  "traits": {                      // required (can be empty {})
    "email": "user@example.com",
    "name": "Jane Doe"
  },
  "timestamp": "2025-12-15T10:30:00Z"
}
```

**Validation:**
- `user_id` must be string or numeric
- `traits` must be a hash/object

**Return Value:**
```ruby
true   # on success (2xx)
false  # on failure
```

---

#### 6d. SessionRequest

**File:** `lib/mbuzz/client/session_request.rb`

**Endpoint:** `POST /sessions`

**Payload:**
```json
{
  "session": {
    "visitor_id": "abc123...",     // required
    "session_id": "xyz789...",     // required
    "url": "https://...",          // required
    "referrer": "https://...",     // optional
    "started_at": "2025-12-15T10:30:00Z"
  }
}
```

**Validation:**
- `visitor_id`, `session_id`, `url` must all be present

**Return Value:**
```ruby
true   # on success
false  # on failure
```

**Note:** Called asynchronously from middleware - never blocks requests.

---

### Component 7: Public API

**File:** `lib/mbuzz.rb`

**4-Call Model:**

```ruby
# 1. Initialize
Mbuzz.init(
  api_key: "sk_live_xxx",
  api_url: "https://mbuzz.co/api/v1",  # optional
  debug: false,                         # optional
  skip_paths: ["/admin"],               # optional
  skip_extensions: [".pdf"]             # optional
)

# 2. Track Event
Mbuzz.event("page_view", page_title: "Home")
# → Auto-adds url, referrer from RequestContext
# → Auto-adds visitor_id, session_id, user_id from middleware

# 3. Track Conversion
Mbuzz.conversion("purchase",
  revenue: 99.99,
  order_id: "ORD-123"
)

# With acquisition tracking:
Mbuzz.conversion("signup",
  user_id: "user_123",
  is_acquisition: true
)

# Recurring revenue (inherits original attribution):
Mbuzz.conversion("payment",
  user_id: "user_123",
  revenue: 49.00,
  inherit_acquisition: true
)

# 4. Identify User
Mbuzz.identify("user_123", traits: { email: "user@example.com" })
```

**Context Accessors:**
```ruby
Mbuzz.visitor_id   # → from middleware env or fallback
Mbuzz.session_id   # → from middleware env
Mbuzz.user_id      # → from middleware env (app session)
```

---

## Part 3: Language-Specific Translation Notes

### Node.js

| Ruby Concept | Node.js Equivalent |
|--------------|-------------------|
| Rack middleware | Express middleware `(req, res, next) => {}` |
| Thread.current | `AsyncLocalStorage` |
| Net::HTTP | `fetch` or `https` module |
| SecureRandom.hex(32) | `crypto.randomBytes(32).toString('hex')` |
| request.cookies | `req.cookies` (with cookie-parser) |
| Set-Cookie header | `res.cookie()` |
| Thread.new {} | `setImmediate()` or `process.nextTick()` |

### Python

| Ruby Concept | Python Equivalent |
|--------------|-------------------|
| Rack middleware | WSGI middleware or Django middleware |
| Thread.current | `contextvars.ContextVar` |
| Net::HTTP | `requests` or `httpx` |
| SecureRandom.hex(32) | `secrets.token_hex(32)` |
| request.cookies | `request.COOKIES` (Django) / `request.cookies` (Flask) |
| Set-Cookie header | `response.set_cookie()` |
| Thread.new {} | `threading.Thread` or `asyncio.create_task()` |

### PHP

| Ruby Concept | PHP Equivalent |
|--------------|----------------|
| Rack middleware | PSR-15 middleware or Laravel middleware |
| Thread.current | Request attributes or `$_SERVER` superglobal |
| Net::HTTP | `curl` or Guzzle |
| SecureRandom.hex(32) | `bin2hex(random_bytes(32))` |
| request.cookies | `$_COOKIE` |
| Set-Cookie header | `setcookie()` or `Response::cookie()` |
| Thread.new {} | Queue job or `register_shutdown_function()` |

---

## Part 4: API Endpoints Summary

| Endpoint | Method | Purpose | Returns Response? |
|----------|--------|---------|-------------------|
| `/events` | POST | Track events | Yes (event_id) |
| `/conversions` | POST | Track conversions | Yes (conversion_id, attribution) |
| `/identify` | POST | Link visitor to user | No (boolean) |
| `/sessions` | POST | Create session | No (boolean) |

---

## Part 5: Constants Reference

```ruby
# Cookie names
VISITOR_COOKIE_NAME = "_mbuzz_vid"
SESSION_COOKIE_NAME = "_mbuzz_sid"

# Cookie expiry
VISITOR_COOKIE_MAX_AGE = 63_072_000  # 2 years in seconds
SESSION_COOKIE_MAX_AGE = 1_800       # 30 minutes in seconds

# Cookie attributes
VISITOR_COOKIE_PATH = "/"
VISITOR_COOKIE_SAME_SITE = "Lax"

# Env keys (for storing in request)
ENV_USER_ID_KEY = "mbuzz.user_id"
ENV_VISITOR_ID_KEY = "mbuzz.visitor_id"
ENV_SESSION_ID_KEY = "mbuzz.session_id"

# API paths
EVENTS_PATH = "/events"
IDENTIFY_PATH = "/identify"
CONVERSIONS_PATH = "/conversions"
SESSIONS_PATH = "/sessions"
```

---

## Part 6: CRITICAL - Reset State Each Request (Bug Fix)

### The Bug

Middleware instances are **reused across requests**. Without explicit reset, memoized values leak between requests:

```
Request 1: User A → visitor_id = "aaa", session_id = "111"
Request 2: User B → visitor_id = "aaa" ← WRONG! Still has User A's ID
```

### The Fix

**MUST clear memoized instance variables at the start of every request:**

```ruby
# Ruby SDK - lib/mbuzz/middleware/tracking.rb:52
def reset_request_state!
  @request = nil
  @visitor_id = nil
  @session_id = nil
  @user_id = nil
end
```

### Translation to Other Languages

**Node.js (Express):**
```javascript
// ❌ BAD - Don't use module-level variables
let visitorId, sessionId;

app.use((req, res, next) => {
  // visitorId from previous request leaks!
});

// ✅ GOOD - Always read fresh from req
app.use((req, res, next) => {
  const visitorId = req.cookies._mbuzz_vid || generateId();
  const sessionId = req.cookies._mbuzz_sid || generateId();
  // ...
});
```

**Python (Django/Flask):**
```python
# ❌ BAD - Don't store on self in middleware class
class MbuzzMiddleware:
    def __init__(self):
        self.visitor_id = None  # Shared across requests!

# ✅ GOOD - Store on request object
def process_request(self, request):
    request.mbuzz_visitor_id = self._get_or_create_visitor_id(request)
```

**PHP (Laravel):**
```php
// PHP is stateless per-request by default - less risk
// But avoid static properties!

// ❌ BAD
class MbuzzMiddleware {
    private static $visitorId;  // Persists in long-running processes!
}

// ✅ GOOD
class MbuzzMiddleware {
    public function handle($request, Closure $next) {
        $visitorId = $request->cookie('_mbuzz_vid') ?? $this->generateId();
        // ...
    }
}
```

### Key Principle

**Never memoize request-specific data at the middleware class level.** Either:
1. Reset at start of each request (Ruby pattern)
2. Store on request object (Python/PHP pattern)
3. Use only local variables (Node.js pattern)

---

## Part 7: Multi-Language README Template

Each SDK should have an identical README structure with language-specific examples:

### README Structure

```markdown
# mbuzz-{language}

Server-side multi-touch attribution for {Language}. Track customer journeys,
attribute conversions, know which channels drive revenue.

## Installation

{language-specific install command}

## Quick Start

### 1. Initialize

{init code}

### 2. Track Events

{event code}

### 3. Track Conversions

{conversion code}

### 4. Identify Users

{identify code}

## {Framework} Integration

{framework-specific middleware setup}

## Configuration Options

{init options table}

## The 4-Call Model

| Method | When to Use |
|--------|-------------|
| `init` | Once on app boot |
| `event` | User interactions, funnel steps |
| `conversion` | Purchases, signups, any revenue event |
| `identify` | Login, signup, when you know the user |

## Error Handling

{language} SDK never raises exceptions. All methods return `false`/`None`/`null` on failure.

## Requirements

- {Language} {version}+
- {Framework} {version}+ (for automatic integration)

## Links

- [Documentation](https://mbuzz.co/docs)
- [Dashboard](https://mbuzz.co/dashboard)

## License

MIT License
```

### Language-Specific Examples

Already defined in `config/sdk_registry.yml`:
- `install_command`
- `init_code`
- `event_code`
- `conversion_code`
- `identify_code`
- `middleware_code`

---

## Part 8: Files to Update in Multibuzz App

### Files to Modify

| File | Change |
|------|--------|
| `config/sdk_registry.yml` | Update code examples, add middleware_code for new SDKs |
| `app/views/docs/_getting_started.html.erb` | Add Node.js, Python tabs to code_tabs |
| `app/views/docs/shared/_code_tabs.html.erb` | May need syntax highlighting for new languages |
| `app/views/onboarding/install.html.erb` | Uses `current_sdk` - already dynamic |
| `app/views/onboarding/verify.html.erb` | Uses `current_sdk` - already dynamic |
| `app/views/onboarding/conversion.html.erb` | Uses `current_sdk` - check for updates |

### New Files to Create

| File | Purpose |
|------|---------|
| `app/views/shared/icons/sdks/nodejs.svg` | Node.js icon for SDK picker |
| `app/views/shared/icons/sdks/python.svg` | Python icon (if not exists) |
| `app/views/docs/_nodejs_quickstart.html.erb` | Node.js-specific docs (optional) |
| `app/views/docs/_python_quickstart.html.erb` | Python-specific docs (optional) |

### sdk_registry.yml Updates Needed

For each new SDK, ensure complete code examples:

```yaml
nodejs:
  # ... existing fields ...
  middleware_code: |
    // Express middleware
    const mbuzz = require('mbuzz');
    app.use(mbuzz.middleware());
  verification_command: "mbuzz.event('test', { url: 'https://test.com' });"

python:
  # ... existing fields ...
  middleware_code: |
    # Django - settings.py
    MIDDLEWARE = [
        'mbuzz.middleware.MbuzzMiddleware',
        # ...
    ]

    # Flask
    from mbuzz import MbuzzMiddleware
    app.wsgi_app = MbuzzMiddleware(app.wsgi_app)
```

### Docs code_tabs Updates

Currently only shows `ruby` and `curl`. Need to add:

```erb
<%= code_tabs({
  ruby: { ... },
  nodejs: {
    label: 'Node.js',
    syntax: 'javascript',
    code: <<~CODE
      const mbuzz = require('mbuzz');
      mbuzz.init({ apiKey: process.env.MBUZZ_API_KEY });
    CODE
  },
  python: {
    label: 'Python',
    syntax: 'python',
    code: <<~CODE
      import mbuzz
      mbuzz.init(api_key=os.environ['MBUZZ_API_KEY'])
    CODE
  },
  curl: { ... }
}, default: :ruby) %>
```

---

## Part 9: Node.js SDK Implementation Checklist

### Project Setup

- [ ] Create repo: `mbuzz-node`
- [ ] Initialize npm package: `npm init`
- [ ] Configure TypeScript (optional but recommended)
- [ ] Set up Jest for testing
- [ ] Configure ESLint + Prettier
- [ ] Add GitHub Actions CI/CD
- [ ] Create LICENSE (MIT)

### Package Configuration

```json
{
  "name": "mbuzz",
  "version": "0.1.0",
  "description": "Server-side multi-touch attribution for Node.js",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "exports": {
    ".": {
      "require": "./dist/index.js",
      "import": "./dist/index.mjs"
    }
  },
  "engines": {
    "node": ">=16.0.0"
  },
  "keywords": ["analytics", "attribution", "marketing", "tracking"],
  "repository": "https://github.com/multibuzz/mbuzz-node"
}
```

### Directory Structure

```
mbuzz-node/
├── src/
│   ├── index.ts              # Public API exports
│   ├── mbuzz.ts              # Main module (init, event, conversion, identify)
│   ├── config.ts             # Configuration singleton
│   ├── api.ts                # HTTP client
│   ├── context.ts            # AsyncLocalStorage context
│   ├── middleware/
│   │   └── express.ts        # Express middleware
│   ├── client/
│   │   ├── trackRequest.ts
│   │   ├── identifyRequest.ts
│   │   ├── conversionRequest.ts
│   │   └── sessionRequest.ts
│   └── utils/
│       └── identifier.ts     # Visitor ID generation
├── test/
│   ├── mbuzz.test.ts
│   ├── api.test.ts
│   ├── middleware.test.ts
│   └── client/
├── dist/                     # Compiled output
├── README.md
├── CHANGELOG.md
├── package.json
├── tsconfig.json
└── jest.config.js
```

### Implementation Checklist

#### Phase 1: Core Infrastructure

- [ ] **config.ts** - Configuration module
  - [ ] Default values (apiUrl, timeout, skipPaths, skipExtensions)
  - [ ] `init()` function to set config
  - [ ] Validation (api_key required)
  - [ ] Export config singleton

- [ ] **api.ts** - HTTP client
  - [ ] `post(path, payload)` → boolean
  - [ ] `postWithResponse(path, payload)` → object | null
  - [ ] Headers: Authorization, Content-Type, User-Agent
  - [ ] SSL verification
  - [ ] Timeout handling (default 5s)
  - [ ] Never throw - return false/null on error
  - [ ] Debug logging when enabled

- [ ] **utils/identifier.ts** - ID generation
  - [ ] `generateId()` → 64-char hex string
  - [ ] Use `crypto.randomBytes(32).toString('hex')`

- [ ] **context.ts** - Request context (AsyncLocalStorage)
  - [ ] `withContext(request, callback)` - run with context
  - [ ] `getContext()` - get current context
  - [ ] `enrichProperties(custom)` - add url, referrer
  - [ ] Test with concurrent requests

#### Phase 2: Request Classes

- [ ] **client/trackRequest.ts**
  - [ ] Constructor: visitorId, sessionId, userId, eventType, properties
  - [ ] Validation: eventType required, properties is object, has identifier
  - [ ] Payload: events array with timestamp
  - [ ] Return: `{ success, eventId, eventType, visitorId, sessionId }`

- [ ] **client/conversionRequest.ts**
  - [ ] Constructor: eventId, visitorId, userId, conversionType, revenue, currency, isAcquisition, inheritAcquisition, properties
  - [ ] Validation: conversionType required, has at least one identifier
  - [ ] Payload: conversion object
  - [ ] Return: `{ success, conversionId, attribution }`

- [ ] **client/identifyRequest.ts**
  - [ ] Constructor: userId, visitorId, traits
  - [ ] Validation: userId is string/number, traits is object
  - [ ] Payload: user_id, visitor_id, traits, timestamp
  - [ ] Return: boolean

- [ ] **client/sessionRequest.ts**
  - [ ] Constructor: visitorId, sessionId, url, referrer, startedAt
  - [ ] Validation: visitorId, sessionId, url required
  - [ ] Payload: session object
  - [ ] Return: boolean

#### Phase 3: Express Middleware

- [ ] **middleware/express.ts**
  - [ ] Export middleware function: `mbuzz.middleware()`
  - [ ] Path filtering (skipPaths, skipExtensions)
  - [ ] Read cookies: `_mbuzz_vid`, `_mbuzz_sid`
  - [ ] Generate IDs if missing
  - [ ] Store on `req.mbuzz = { visitorId, sessionId, userId }`
  - [ ] Set cookies on response (with correct attributes)
  - [ ] Create session async if new (use `setImmediate`)
  - [ ] Wrap with AsyncLocalStorage context
  - [ ] **CRITICAL**: No module-level memoization!

- [ ] Cookie configuration:
  - [ ] `_mbuzz_vid`: 2 years, HttpOnly, SameSite=Lax, Secure (if HTTPS)
  - [ ] `_mbuzz_sid`: 30 minutes, HttpOnly, SameSite=Lax, Secure (if HTTPS)

#### Phase 4: Public API

- [ ] **mbuzz.ts** - Main module
  - [ ] `init(options)` - configure SDK
  - [ ] `event(eventType, properties)` - track event
  - [ ] `conversion(conversionType, options)` - track conversion
  - [ ] `identify(userId, options)` - identify user
  - [ ] Context accessors: `visitorId`, `sessionId`, `userId`
  - [ ] Auto-enrich properties with url/referrer from context

- [ ] **index.ts** - Public exports
  - [ ] Export: init, event, conversion, identify
  - [ ] Export: middleware
  - [ ] Export: visitorId, sessionId, userId accessors
  - [ ] Export types (TypeScript)

#### Phase 5: Testing

- [ ] Unit tests for each module
- [ ] Integration tests for middleware
- [ ] Test concurrent requests (AsyncLocalStorage isolation)
- [ ] Test cookie handling
- [ ] Test error scenarios (network timeout, invalid config)
- [ ] Test skip paths/extensions

#### Phase 6: Documentation

- [ ] README.md (follow template from Part 7)
- [ ] CHANGELOG.md
- [ ] TypeScript types documentation
- [ ] Express integration guide
- [ ] Next.js integration guide (if applicable)
- [ ] Examples directory

#### Phase 7: Release

- [ ] Publish to npm: `npm publish`
- [ ] Update `config/sdk_registry.yml` in multibuzz app:
  - [ ] Change status to `live`
  - [ ] Add `released_at`
  - [ ] Set `package_url`
- [ ] Update `app/views/docs/_getting_started.html.erb` with Node.js tabs
- [ ] Create SDK icon if missing
- [ ] Test onboarding flow with Node.js selected

### Code Examples

#### init
```javascript
const mbuzz = require('mbuzz');

mbuzz.init({
  apiKey: process.env.MBUZZ_API_KEY,
  apiUrl: 'https://mbuzz.co/api/v1',  // optional
  debug: process.env.NODE_ENV === 'development',
  skipPaths: ['/health', '/admin'],
  skipExtensions: ['.pdf']
});
```

#### middleware
```javascript
const express = require('express');
const mbuzz = require('mbuzz');

const app = express();
app.use(mbuzz.middleware());
```

#### event
```javascript
// Auto-gets visitorId, sessionId from context
mbuzz.event('add_to_cart', { productId: 'SKU-123', price: 49.99 });
```

#### conversion
```javascript
mbuzz.conversion('purchase', {
  revenue: 99.99,
  orderId: order.id
});

// Acquisition conversion
mbuzz.conversion('signup', {
  userId: user.id,
  isAcquisition: true
});

// Recurring with inherited attribution
mbuzz.conversion('payment', {
  userId: user.id,
  revenue: 49.00,
  inheritAcquisition: true
});
```

#### identify
```javascript
mbuzz.identify(user.id, {
  traits: {
    email: user.email,
    name: user.name,
    plan: user.plan
  }
});
```

### Key Implementation Notes

1. **Use `node:crypto`** - Native crypto module, no dependencies
2. **Use `node:https`** - Native HTTP client, no axios/fetch dependencies
3. **AsyncLocalStorage** - For request context isolation (Node 16+)
4. **cookie-parser** - Middleware should work with or without it
5. **TypeScript optional** - Compile to JS for broader compatibility
6. **No external dependencies** - Keep bundle small

### Testing Concurrent Requests

```javascript
test('isolates context between concurrent requests', async () => {
  const results = await Promise.all([
    simulateRequest({ visitorId: 'a' }),
    simulateRequest({ visitorId: 'b' }),
    simulateRequest({ visitorId: 'c' })
  ]);

  expect(results[0].visitorId).toBe('a');
  expect(results[1].visitorId).toBe('b');
  expect(results[2].visitorId).toBe('c');
});
```

---

## Sources

- [Shopify Market Share 2025](https://www.yaguara.co/shopify-market-share/)
- [WooCommerce Market Share 2025](https://redstagfulfillment.com/what-is-woocommerces-market-share/)
- [Magento Market Share Q4 2024-Q1 2025](https://www.mgt-commerce.com/blog/magento-market-share/)
- [Stack Overflow Developer Survey 2025](https://survey.stackoverflow.co/2025/technology)
- [Shopify Server-Side Tracking Guide 2025](https://analyzify.com/hub/server-side-tracking-shopify-guide)
- [Adobe Commerce Module Architecture](https://developer.adobe.com/commerce/php/architecture/modules/overview/)
