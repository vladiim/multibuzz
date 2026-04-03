# Navigation Detection Reference

**Purpose**: Canonical reference for implementing navigation-aware session creation in any mbuzz SDK.

**Since**: SDK v0.7.3 | **Last Updated**: 2026-02-05

---

## Why Navigation Detection Exists

Server-side SDK middleware intercepts **every** HTTP request. Modern web frameworks fire multiple concurrent requests per page load — Turbo frames, htmx partials, prefetch, lazy-loaded fragments. Without navigation detection, each sub-request creates a separate session, inflating visit counts by 3-5x.

**Example**: A Rails app with one lazy-loaded Turbo frame in the navbar fires 2 requests on every page load. 12,000 real visitors become 24,000+ visitor records.

Navigation detection gates session creation so only **real page navigations** (user clicking a link, typing a URL, submitting a form) create sessions. Sub-requests are filtered automatically.

---

## The Algorithm

### Primary Signal: Sec-Fetch-\* Headers (Whitelist)

Modern browsers send `Sec-Fetch-*` headers on every request. These are **forbidden headers** — JavaScript cannot forge them. They tell the server exactly what type of request this is.

**Create a session when ALL conditions are true:**

1. `Sec-Fetch-Mode` equals `navigate`
2. `Sec-Fetch-Dest` equals `document`
3. `Sec-Purpose` header is **absent**

Any other combination → do NOT create a session.

### Fallback: Framework Blacklist (Old Browsers)

When `Sec-Fetch-Mode` is absent (old browsers, bots, non-browser HTTP clients), fall back to checking for known framework headers.

**Do NOT create a session if ANY of these headers are present:**

| Header | Framework |
|--------|-----------|
| `Turbo-Frame` | Hotwire / Turbo (Rails) |
| `HX-Request` | htmx |
| `X-Up-Version` | Unpoly |
| `X-Requested-With: XMLHttpRequest` | jQuery / legacy XHR |

If none are present → create a session (real navigation from an old browser).

### Pseudocode

```
function should_create_session(request):
    mode = request.header("Sec-Fetch-Mode")
    dest = request.header("Sec-Fetch-Dest")

    if mode is present:
        # Modern browser — whitelist real navigations
        return mode == "navigate"
           AND dest == "document"
           AND request.header("Sec-Purpose") is absent

    # Old browser / bot — blacklist known sub-requests
    return request.header("Turbo-Frame") is absent
       AND request.header("HX-Request") is absent
       AND request.header("X-Up-Version") is absent
       AND request.header("X-Requested-With") != "XMLHttpRequest"
```

---

## What to Gate vs What to Allow

| SDK Action | Gated? | Reason |
|------------|--------|--------|
| `POST /sessions` (session creation) | **Yes** | Only real navigations should create sessions |
| Visitor cookie (`_mbuzz_vid`) | **No** | Set on ALL responses so subsequent requests have the cookie |
| `POST /events` (event tracking) | **No** | Application code decides when to track events |
| `POST /conversions` | **No** | Application code decides when to track conversions |

---

## Header Reference

| Request Type | Sec-Fetch-Mode | Sec-Fetch-Dest | Sec-Purpose | Create Session? |
|---|---|---|---|---|
| User clicks link | `navigate` | `document` | _(absent)_ | **Yes** |
| User types URL in address bar | `navigate` | `document` | _(absent)_ | **Yes** |
| Form POST submission | `navigate` | `document` | _(absent)_ | **Yes** |
| `window.open()` / `target="_blank"` | `navigate` | `document` | _(absent)_ | **Yes** |
| Turbo Frame lazy load | `same-origin` | `empty` | | No |
| htmx partial update | `same-origin` | `empty` | | No |
| Unpoly fragment update | `same-origin` | `empty` | | No |
| `fetch()` / XHR | `cors` or `same-origin` | `empty` | | No |
| `<link rel="prefetch">` | `navigate` | `document` | `prefetch` | No |
| Speculative prerender | `navigate` | `document` | `prefetch` | No |
| iframe navigation | `navigate` | `iframe` | | No |
| Service worker fetch | `same-origin` | `empty` | | No |
| WebSocket upgrade | `websocket` | `empty` | | No |
| Image / script / font / CSS | `no-cors` | `image`/`script`/`font`/`style` | | No |
| Old browser — no framework headers | _(absent)_ | _(absent)_ | | **Yes** (fallback) |
| Old browser + Turbo-Frame | _(absent)_ | _(absent)_ | | No (blacklist) |

---

## Implementation by Language

### Ruby (Rack env)

```ruby
def should_create_session?(env)
  mode = env["HTTP_SEC_FETCH_MODE"]
  dest = env["HTTP_SEC_FETCH_DEST"]

  if mode
    return mode == "navigate" &&
           dest == "document" &&
           env["HTTP_SEC_PURPOSE"].nil?
  end

  env["HTTP_TURBO_FRAME"].nil? &&
    env["HTTP_HX_REQUEST"].nil? &&
    env["HTTP_X_UP_VERSION"].nil? &&
    env["HTTP_X_REQUESTED_WITH"] != "XMLHttpRequest"
end
```

Note: Rack converts HTTP headers to `HTTP_` prefix with uppercase and underscores.

### Node.js (Express req.headers)

```typescript
export const shouldCreateSession = (req: Request): boolean => {
  const mode = req.headers['sec-fetch-mode'];
  const dest = req.headers['sec-fetch-dest'];

  if (mode) {
    return mode === 'navigate' &&
      dest === 'document' &&
      !req.headers['sec-purpose'];
  }

  return !req.headers['turbo-frame'] &&
    !req.headers['hx-request'] &&
    !req.headers['x-up-version'] &&
    req.headers['x-requested-with'] !== 'XMLHttpRequest';
};
```

Note: Express lowercases all header names.

### Python (Flask request.headers)

```python
def should_create_session() -> bool:
    mode = request.headers.get("Sec-Fetch-Mode")
    dest = request.headers.get("Sec-Fetch-Dest")

    if mode:
        return (
            mode == "navigate"
            and dest == "document"
            and not request.headers.get("Sec-Purpose")
        )

    return (
        not request.headers.get("Turbo-Frame")
        and not request.headers.get("HX-Request")
        and not request.headers.get("X-Up-Version")
        and request.headers.get("X-Requested-With") != "XMLHttpRequest"
    )
```

Note: Flask preserves original header casing via `request.headers.get()`.

### PHP ($_SERVER)

```php
public static function shouldCreateSession(array $server = []): bool
{
    $server = $server ?: $_SERVER;
    $mode = $server['HTTP_SEC_FETCH_MODE'] ?? null;
    $dest = $server['HTTP_SEC_FETCH_DEST'] ?? null;

    if ($mode !== null) {
        return $mode === 'navigate'
            && $dest === 'document'
            && !isset($server['HTTP_SEC_PURPOSE']);
    }

    return !isset($server['HTTP_TURBO_FRAME'])
        && !isset($server['HTTP_HX_REQUEST'])
        && !isset($server['HTTP_X_UP_VERSION'])
        && ($server['HTTP_X_REQUESTED_WITH'] ?? '') !== 'XMLHttpRequest';
}
```

Note: PHP converts headers to `HTTP_` prefix with uppercase and underscores (like Rack).

---

## Device Fingerprint

All SDKs must compute and send a device fingerprint with session creation requests. The fingerprint enables server-side advisory lock serialization for concurrent requests from the same device.

**Formula**: `SHA256(ip + "|" + user_agent)[0:32]`

**Properties**:
- 32-character lowercase hex string
- Deterministic (same inputs = same output)
- Matches server-side computation exactly

**Implementations**:

| Language | Code |
|----------|------|
| Ruby | `Digest::SHA256.hexdigest("#{ip}\|#{user_agent}")[0, 32]` |
| Node | `createHash('sha256').update(\`${ip}\|${userAgent}\`).digest('hex').substring(0, 32)` |
| Python | `hashlib.sha256(f"{ip}\|{user_agent}".encode()).hexdigest()[:32]` |
| PHP | `substr(hash('sha256', "{$ip}\|{$userAgent}"), 0, 32)` |

**Parity test value**: `SHA256("127.0.0.1|Mozilla/5.0")[0:32]` = `ea687534a507e203bdef87cee3cc60c5`

---

## Testing Checklist

Every SDK must test these scenarios:

### Whitelist Path (Modern Browsers)

| # | Test | Headers | Expected |
|---|------|---------|----------|
| 1 | Real page navigation | `Sec-Fetch-Mode: navigate`, `Sec-Fetch-Dest: document` | Session created |
| 2 | Turbo Frame | `Sec-Fetch-Mode: same-origin`, `Sec-Fetch-Dest: empty`, `Turbo-Frame: content` | No session |
| 3 | htmx partial | `Sec-Fetch-Mode: same-origin`, `Sec-Fetch-Dest: empty`, `HX-Request: true` | No session |
| 4 | fetch/XHR | `Sec-Fetch-Mode: cors`, `Sec-Fetch-Dest: empty` | No session |
| 5 | Prefetch | `Sec-Fetch-Mode: navigate`, `Sec-Fetch-Dest: document`, `Sec-Purpose: prefetch` | No session |
| 6 | iframe | `Sec-Fetch-Mode: navigate`, `Sec-Fetch-Dest: iframe` | No session |

### Blacklist Fallback (Old Browsers)

| # | Test | Headers | Expected |
|---|------|---------|----------|
| 7 | No framework headers | _(empty)_ | Session created |
| 8 | Turbo-Frame present | `Turbo-Frame: banner` | No session |
| 9 | HX-Request present | `HX-Request: true` | No session |
| 10 | XMLHttpRequest | `X-Requested-With: XMLHttpRequest` | No session |
| 11 | Unpoly present | `X-Up-Version: 3.0` | No session |

### Integration

| # | Test | Expected |
|---|------|----------|
| 12 | Navigation request → `POST /sessions` called | Session payload includes visitor_id, session_id, device_fingerprint |
| 13 | Turbo frame request → `POST /sessions` NOT called | No API call made |
| 14 | Visitor cookie set on ALL responses | Cookie present even on sub-requests |
| 15 | Fingerprint parity | `SHA256("127.0.0.1\|Mozilla/5.0")[0:32]` = `ea687534a507e203bdef87cee3cc60c5` |

---

## Edge Cases

### HTTPS Requirement

`Sec-Fetch-*` headers are only sent over HTTPS. HTTP requests hit the blacklist fallback path. All production SDKs should be deployed behind HTTPS.

### Bots and Crawlers

Bots typically don't send `Sec-Fetch-*` headers. They hit the blacklist fallback path. If no framework headers are present, a session is created. This is acceptable — bot traffic is usually filtered at a different layer.

### Redirects (3xx)

`Sec-Fetch-Mode` stays `navigate` through the entire redirect chain. `Sec-Fetch-Site` is recalculated per hop. No impact on navigation detection — redirected navigations are real navigations.

### Service Worker Cache Hits

If a service worker serves the response from cache, the request never reaches the server. No session is created. This is acceptable — cached pages have no server visibility.

### Client-Side SDKs

Browser JavaScript cannot read `Sec-Fetch-*` headers (they are forbidden headers). Client-side SDKs (JavaScript, Shopify theme extensions) are exempt from navigation detection. They don't intercept HTTP requests via middleware — they explicitly call `fetch()` for tracking.

---

## Browser Support for Sec-Fetch-\*

| Browser | Support Since |
|---------|-------------|
| Chrome | 76 (July 2019) |
| Edge | 79 (January 2020) |
| Firefox | 90 (July 2021) |
| Safari | 16.4 (March 2023) |

Essentially universal for current browser versions. The blacklist fallback handles the long tail.

---

## Related Documentation

- [SDK Specification](./sdk_specification.md) — full SDK requirements
- [API Contract](./api_contract.md) — `POST /sessions` endpoint details
- [SDK Registry](./sdk_registry.md) — SDK versions and features
- [Navigation-Aware Session Creation Spec](../../specs/navigation_aware_session_creation_spec.md) — incident analysis and implementation plan
