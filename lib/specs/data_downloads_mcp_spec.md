# Data Downloads MCP Server Specification

**Date:** 2026-05-13 (research decisions resolved 2026-05-15)
**Priority:** P1
**Status:** Ready to start — library, transport, hosting, and naming decided (see [Key Decisions](#key-decisions))
**Branch:** `feat/data-downloads-mcp` off `main` (`feat/conversion-feedback` deployed 2026-05-15)
**Depends on:** `old/data_downloads_api_spec.md` — **shipped 2026-05-12**. The three JSON endpoints, query services, and namespace (`DataDownloads::*`) are live; this spec wraps them as MCP tools.

---

## Summary

Expose mbuzz attribution, funnel, and spend data through the Model Context Protocol (MCP) so customers can plug their account into Claude Desktop, ChatGPT, Cursor, and any other MCP-aware AI client. The MCP server reuses the JSON endpoints from `data_downloads_api_spec.md` — same auth, same scopes, same data — wrapped in MCP's tool-call protocol so an AI agent can pull a customer's data into a conversation without the customer pasting CSVs or building a custom integration.

This unlocks the workflow that today is the API spec's hidden hard part: turning "your data is in an API" into "your data is in your AI assistant." The API is for engineers; MCP is for marketers.

---

## Current State

No MCP surface exists. References to MCP in the repo are marketing copy on landing pages only (`vs_ga4.html.erb`, `vs_hyros.html.erb`, etc.). No gem dependency, no server code, no transport. Greenfield.

The data the MCP server will expose is the data the API spec ships (shipped 2026-05-12):

| Resource | API endpoint | Query service | Underlying scope |
|----------|--------------|---------------|------------------|
| Conversions | `GET /api/v1/data/conversions` | `DataDownloads::ConversionsQueryService` | `Dashboard::Scopes::FilteredCreditsScope` |
| Funnel | `GET /api/v1/data/funnel` | `DataDownloads::FunnelQueryService` | `SessionsScope` + `EventsScope` + `ConversionsScope` |
| Spend | `GET /api/v1/data/spend` | `DataDownloads::SpendQueryService` | `SpendIntelligence::Scopes::SpendScope` |

All three return `{ data: [...], meta: { total_count, page, per_page, total_pages } }` shaped responses. Auth uses existing API keys (`sk_test_*` / `sk_live_*`) with environment-determined data scope. Account isolation, revocation, audit logging — all inherited from `ApiKeys::AuthenticationService` and `Api::V1::BaseController`.

### Data Flow (Current — none)

```
(no MCP)
```

---

## Proposed Solution

A streamable-HTTP MCP server at `mcp.mbuzz.co`, hosted on the `mbuzz-shopify` droplet (see [Key Decisions](#key-decisions)), authenticated by the same API key the JSON API uses. The server exposes three MCP **tools**, each a thin shim over a JSON endpoint:

- `mbuzz_get_conversions`
- `mbuzz_get_funnel`
- `mbuzz_get_spend`

Plus one **resource** (`mbuzz://account/summary`) that returns a one-shot overview the AI can read at conversation start: account name, date of first event, list of active SDKs, active ad platforms, default attribution model. This is the "load my context" affordance — it lets the agent give grounded answers without 50 tool calls.

### Why MCP (Not Just the API)

| Consideration | MCP | Raw API |
|---|---|---|
| Discovery | Tools self-describe to the client | Customer must read docs |
| Auth | Standard bearer flow over HTTP/SSE | Same |
| Pagination | Client iterates via `next_cursor` in tool result | Same |
| Caller | AI agent, with autonomy to pick which tool | Human / scripted client |
| UX | "Plug mbuzz into Claude. Ask questions." | "Build an integration." |

The API spec ships a programmatic surface for engineers. MCP ships an AI-native surface for marketers and analysts who don't write code but live in Claude / ChatGPT.

### Why Streamable HTTP (Not stdio)

| Transport | Hosting model | Fit |
|---|---|---|
| **stdio** | Customer runs the server locally (Node / Python) | Wrong fit — would mean we ship a customer-side binary and they configure env vars with their API key. Friction. |
| **Streamable HTTP** | mbuzz hosts the server, customer adds the URL to their MCP client | Customer pastes API key, pastes URL, done. Centralised auth + rate limiting on our side. |

Streamable HTTP is the post-2025-03-26 successor to SSE in the MCP spec. Bearer auth in the HTTP header, server-sent events for streaming responses if needed.

### Run in stateless mode

The official SDK's streamable HTTP transport stores session state in-memory, which would otherwise force single-process deployment or sticky-session routing. **Run with `stateless: true`.** Our tool surface is read-only with no session continuity — each tool call is an independent, separately-authenticated request. Stateless mode drops the in-memory session store entirely, which means the host droplet needs no sticky routing and the surface scales horizontally if it ever needs to.

### Auth Model

The MCP client sends `Authorization: Bearer sk_{env}_{key}` on every HTTP call (request + every subsequent SSE message). Server validates via `ApiKeys::AuthenticationService` — exact same code path as the JSON API. Account, env (test vs live), revocation state, suspended-account check: all reused.

No new credentials. No OAuth dance. No per-tool scopes (yet). The API key is the account's identity to the MCP server.

### Tool Surface

Each tool's input schema mirrors the matching JSON endpoint's query parameters. Output is the same `{ data: [...], meta: { ... } }` shape, returned as MCP tool result content with type `application/json`.

```
mbuzz_get_conversions(start_date, end_date, channels?, funnel?, page?, per_page?)
mbuzz_get_funnel(start_date, end_date, channels?, funnel?, page?, per_page?)
mbuzz_get_spend(start_date, end_date, channels?, page?, per_page?)
```

Tool descriptions (the strings the AI reads to decide which tool to call) are written for an agent, not a human:

> `mbuzz_get_spend` — Returns one row per ad spend record from the customer's connected ad platforms (Google Ads, Meta, etc.). Each row has spend, impressions, clicks, platform conversions, and any operator-applied metadata tags. Use when the user asks about ad costs, ROAS, campaign performance, or "what are we spending on X". Date range required; default to last 30 days if unspecified.

### Resource Surface

```
mbuzz://account/summary
```

Returned as `application/json`. Lets the agent prime itself before answering:

```json
{
  "account_name": "Acme Co",
  "first_event_at": "2025-11-04",
  "currency": "USD",
  "active_sdks": ["ruby", "shopify"],
  "active_ad_platforms": ["google_ads", "meta_ads"],
  "default_attribution_model": "linear",
  "available_funnels": ["sales", "trial_signup"]
}
```

### Data Flow (Proposed)

```
Claude Desktop / Cursor / ChatGPT
  → POST mcp.mbuzz.co/mcp (Authorization: Bearer sk_live_...)
    → kamal-proxy on the main web droplet, host-alias routes mcp.mbuzz.co
    → Mcp::ServerController (main Rails app, POST /mcp route)
      → authenticate via ApiKeys::AuthenticationService
      → Mcp::ServerFactory builds a per-request MCP::Server (stateless)
      → server.handle_json dispatches the tool call
        → DataDownloads::ConversionsQueryService / FunnelQueryService / SpendQueryService
          → existing scopes
          → JSON result → MCP tool_result content
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `Gemfile` | Official `mcp` gem (`modelcontextprotocol/ruby-sdk`) | ✅ Done |
| `app/controllers/mcp/server_controller.rb` | `Mcp::ServerController` — auth + `handle_json` dispatch | ✅ Done |
| `app/services/mcp/server_factory.rb` | `Mcp::ServerFactory.build` — per-request `MCP::Server` | ✅ Done (tools/resources arrays filled in Phase 2/3) |
| `app/services/mcp/tools/get_conversions.rb` | Conversions tool — delegates to `DataDownloads::ConversionsQueryService` | **Create (Phase 2)** |
| `app/services/mcp/tools/get_funnel.rb` | Funnel tool — delegates to `DataDownloads::FunnelQueryService` | **Create (Phase 2)** |
| `app/services/mcp/tools/get_spend.rb` | Spend tool — delegates to `DataDownloads::SpendQueryService` | **Create (Phase 2)** |
| `app/services/mcp/resources/account_summary.rb` | Account summary resource | **Create (Phase 3)** |
| `config/routes.rb` | `post "/mcp"` → `mcp/server#handle` | ✅ Done |
| `app/controllers/api/v1/base_controller.rb` | No change — MCP doesn't go through it (separate auth surface) | unchanged ✅ |
| `app/services/data_downloads/{conversions,funnel,spend}_query_service.rb` | Reused from API spec (shipped 2026-05-12) | unchanged |
| `app/views/docs/mcp.html.erb` | Customer-facing MCP setup docs | **Create** |
| `app/views/accounts/api_keys/show.html.erb` | Add "Use this key with MCP" block with the URL + setup snippet | **Edit** |

### Choice of MCP Library — decided 2026-05-15

**Use the official `modelcontextprotocol/ruby-sdk` (gem name `mcp`).** Research on 2026-05-15:

| Option | Verdict | Notes |
|---|---|---|
| **`mcp` — official Ruby SDK** | ✅ **Chosen** | v0.16.0 released 2026-05-14, actively maintained. True streamable HTTP transport (post-2025-03-26 standard). Rack-mountable: `mount transport => "/mcp"`. Custom header auth — we read `Authorization` ourselves and resolve the account. `stateless: true` mode available. |
| `fast-mcp` | ❌ Rejected | v1.6.0, last release Sept 2025 (stale). Its "HTTP" is the legacy SSE transport, not streamable HTTP. **Dealbreaker: auth is a single static `auth_token` string** — cannot resolve a per-account API key through `ApiKeys::AuthenticationService`. |
| Roll our own | ❌ | MCP protocol is non-trivial (handshake, capability negotiation, content types). No reason. |
| Node sidecar | ❌ | Extra service to operate. Unnecessary now that the official Ruby SDK covers streamable HTTP. |

**Caveat:** the official SDK is pre-1.0 — its API may shift before 1.0. Acceptable: it's the official, actively-shipped implementation and this spec is greenfield. Pin the exact version in `Gemfile.lock` and review release notes on each bump.

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Initial handshake | MCP client connects with valid key | Server returns capabilities: 3 tools + 1 resource |
| Tool call — happy path | Valid args, data present | Returns `tool_result` with `{ data: [...], meta: {...} }` |
| Tool call — empty result | Valid args, no matching rows | Returns `tool_result` with `{ data: [], meta: { total_count: 0, ... } }` |
| Tool call — paginated | `per_page` exceeded | First page returned with `meta.total_pages > 1`; agent can call again with `page+1` |
| Missing auth header | No `Authorization` | 401 — connection rejected before handshake |
| Invalid key | Bad token | 401 with `{ error: "Invalid or expired API key" }` |
| Revoked key | Key revoked mid-session | 401 on next call; connection terminated |
| Suspended account | Account not active | 401 on next call |
| Test key | `sk_test_*` | Tools return test data; account summary marked `"environment": "test"` |
| Live key | `sk_live_*` | Tools return live data; account summary marked `"environment": "live"` |
| Bad arg shape | `start_date=foo` | Tool returns `is_error: true` with parseable message; client surfaces to agent |
| Date range too wide | `end - start > 365d` | Same — `is_error: true`, agent can retry with smaller window |
| Resource read — account/summary | Valid key | Returns JSON snapshot |
| Cross-account | Account A's key | Never returns account B's data |

---

## Implementation Tasks

### Phase 1: Auth + transport foundation ✅ (2026-05-15)

Shipped in commits `54b2785` (gem) + `4be2085` (foundation). 7 controller tests green, full suite green (3932).

**Structure landed differently from the original plan — three decisions made during the spike:**

1. **Controller action, not `mount transport`.** The SDK's `StreamableHTTPTransport` carries an in-memory session store. For a stateless, read-only surface a plain controller action that calls `MCP::Server#handle_json` on the request body is genuinely stateless — a fresh server per request, no session store at all. `mount transport` was not used.
2. **Code lives in `app/services/mcp/`, not `app/mcp/`.** Making `app/mcp` a Zeitwerk root would map `app/mcp/server.rb` → top-level `Server` and `app/mcp/tools/*` → top-level `Tools::*`, colliding with everything. `app/services/mcp/` autoloads cleanly as `Mcp::*` with zero config. Controllers stay at `app/controllers/mcp/` → `Mcp::ServerController` (already namespaced).
3. **Auth is a controller `before_action`, not a Rack middleware.** No `app/mcp/authentication.rb`. The controller reuses `ApiKeys::AuthenticationService` directly in a `before_action`, independent of `Api::V1::BaseController`.

- [x] **1.1** Official `mcp` gem added to `Gemfile`, pinned `0.16.0`, `bundle install`, committed
- [x] **1.2** Spike: confirmed via real tests — `MCP::Server#handle_json` processes JSON-RPC, `server_context` flows to the tool layer, the `initialize` handshake and `tools/list` both work. (Error-model confirmation for Open Question #4 deferred to Phase 2 when the first tool exists.)
- [x] **1.3** `Mcp::ServerController#authenticate_api_key` `before_action` — bearer-token check via `ApiKeys::AuthenticationService`, sets `@current_account` / `@current_api_key`
- [x] **1.4** `post "/mcp"` route → `mcp/server#handle`. Not host-constrained — kamal-proxy routes `mcp.mbuzz.co`; the `/mcp` path collides with nothing on the main app.
- [x] **1.5** `test/controllers/mcp/server_controller_test.rb`: valid key → handshake; no/invalid/revoked/suspended key → 401; notification → 202
- [x] **1.6** `Api::V1::BaseController` untouched — `Mcp::ServerController < ActionController::API` with its own auth

### Phase 2: Tool surface ✅ (2026-05-15)

Shipped in commit `67f1f73`. Code at `app/services/mcp/tools/`, tests at `test/services/mcp/tools_test.rb` (one file covers all three). Full suite green (3939).

- [x] **2.1** `Mcp::Tools::GetConversions` → `DataDownloads::ConversionsQueryService`
- [x] **2.2** Tests: each tool returns `{ data, meta }`; bad date → MCP error response (`isError: true`), not a raised exception
- [x] **2.3** `Mcp::Tools::GetFunnel` → `DataDownloads::FunnelQueryService`
- [x] **2.4** `Mcp::Tools::GetSpend` → `DataDownloads::SpendQueryService`
- [x] **2.5** Descriptions written agent-first, intent-focused, under ~300 chars
- [x] **2.6** Cross-account isolation: a fresh account sees zero rows; tools read `server_context[:account]`. Per-platform query services already carry their own isolation tests.

**Notes:**
- A shared `Mcp::Tools::Base` holds the param-building, `test_mode`-from-API-key, and response-formatting logic. Each tool subclass declares its own `tool_name` / `description` / `input_schema` and a one-line `call`.
- Tool `call` takes `(server_context:, **args)` — args land in a hash rather than enumerated kwargs. Robust to unknown args and keeps the param count within rubocop limits.
- `input_schema` must omit `required:` entirely when nothing is required — JSON Schema draft-04 rejects `required: []`.
- `test_mode` is derived from the API key (`server_context[:api_key].test?`), never a tool argument — the key decides test vs live, same as the JSON API.

### Phase 3: Resource

- [ ] **3.1** Create `app/mcp/resources/account_summary.rb` — JSON snapshot of account name, currency, active SDKs (from `SdkRegistry` × account integrations), active ad platforms (from `AdPlatformConnection.active`), default attribution model, available funnels
- [ ] **3.2** Test: resource read returns expected shape; reflects current state of account
- [ ] **3.3** Test: resource respects account isolation

### Phase 4: Customer-facing setup

- [ ] **4.1** Create `app/views/docs/mcp.html.erb` — "How to connect mbuzz to Claude / ChatGPT / Cursor" with the MCP server URL + bearer-key snippet for each client. `skip_marketing_analytics` if it renders the URL with example key (it won't — placeholder only)
- [ ] **4.2** Edit `app/views/accounts/api_keys/show.html.erb` — add a collapsible "Use this key with MCP" block showing the server URL and a copy-paste-ready snippet that references "this key". **Must already be `skip_marketing_analytics`** (it shows the key).
- [ ] **4.3** Link to MCP docs from the API docs index
- [ ] **4.4** Flip the dashboard Export dropdown MCP row from greyed "soon" to a live link to `/docs/mcp` — this is the trigger that supersedes the placeholder in `data_downloads_surface_and_uat_spec.md`. Remove `data-disabled`, add `href`.

### Phase 5: Manual verification (MCP UAT)

The structure mirrors the API UAT in `data_downloads_surface_and_uat_spec.md`: auth boundary → tool calls → resource reads → cross-checks against dashboard → edge cases. Walk step-by-step against prod once Phases 1-4 land.

- [ ] **5.1** Connect Claude Desktop with `sk_test_*` key against prod — verify all 3 tools callable, resource readable
- [ ] **5.2** Repeat with `sk_live_*` — verify env-scoping holds (test client cannot see live data and vice versa)
- [ ] **5.3** Ask Claude in conversation: "What's our blended ROAS in the last 30 days?" → confirm it picks `mbuzz_get_spend` + `mbuzz_get_conversions` and produces a grounded answer
- [ ] **5.4** Revoke the key mid-conversation → next tool call returns 401, agent surfaces the error
- [ ] **5.5** Cross-check: tool-call totals match the dashboard totals for the same window and filters (same reconciliation as API steps A5.1-A5.3)
- [ ] **5.6** Connect ChatGPT and Cursor with the same key — verify each completes a representative tool call
- [ ] **5.7** Tick `data_downloads_surface_and_uat_spec.md` M0 + M1 when this phase signs off

### Phase 5b: Deploy — `mcp.mbuzz.co` host alias on the main web droplet

The MCP server is `POST /mcp` in the main Rails app, so it ships with the next normal deploy of the app. The only extra work is pointing the `mcp.` subdomain at the existing web droplet. No separate Kamal role, no separate droplet — the `mbuzz-shopify` plan was dropped when the Shopify channel was killed (2026-05-15).

- [ ] **5b.1** Create the `mcp.mbuzz.co` DNS A record → the main web droplet (`68.183.173.51`).
- [ ] **5b.2** Add `mcp.mbuzz.co` to the kamal-proxy host list for the web role in `config/deploy.yml` so the proxy answers (and issues a Let's Encrypt cert) for the new host.
- [ ] **5b.3** `kamal deploy`; verify `https://mcp.mbuzz.co/mcp` answers an `initialize` handshake.
- [ ] **5b.4** Verify `https://mbuzz.co/mcp` still answers too (same route) — the subdomain is cosmetic, the path is not host-constrained.

### Phase 6: Ship

- [ ] **6.1** Full test suite passes
- [ ] **6.2** Manual QA from Phase 5 signed off
- [ ] **6.3** MCP docs page live
- [ ] **6.4** API keys page surfaces MCP connection details
- [ ] **6.5** Spec archived to `old/`

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Bearer auth | `test/mcp/authentication_test.rb` | Valid key → account set; invalid → 401; revoked → 401; suspended → 401 |
| Conversions tool | `test/mcp/tools/get_conversions_test.rb` | Tool result shape, pagination, account isolation, bad-arg handling |
| Funnel tool | `test/mcp/tools/get_funnel_test.rb` | Same shape, funnel param, account isolation |
| Spend tool | `test/mcp/tools/get_spend_test.rb` | Spend in major units, metadata as JSON object, account isolation |
| Account summary | `test/mcp/resources/account_summary_test.rb` | Reflects account state, env-aware, account isolation |

### Integration Tests

| Test | File | Verifies |
|------|------|----------|
| Handshake | `test/mcp/server_test.rb` | Capabilities advertised, all 3 tools + 1 resource present |
| End-to-end tool call | Same | POST → auth → tool dispatch → query service → JSON response |
| Test vs live isolation | Same | `sk_test_*` connection cannot see live data |

### Manual QA

See Phase 5 above. The "real-world agent grounding" check is what catches design failures — descriptions that confuse the model, schemas that read awkwardly, missing context the resource should carry.

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Transport | Streamable HTTP, `stateless: true` | We host. Customer pastes URL + key, no local server. Stateless drops the in-memory session store — no sticky routing on the droplet. |
| Auth | Existing API keys | Zero new credential surface. Account scoping, env, revocation, logging — already built. |
| Library | Official `mcp` SDK (`modelcontextprotocol/ruby-sdk`) | Decided 2026-05-15. True streamable HTTP, Rack-mountable, custom header auth so we resolve per-account keys. `fast-mcp` rejected — stale + static-token auth. |
| Hosting | `mcp.mbuzz.co` → the main web droplet | Revised 2026-05-15. The MCP server is just `POST /mcp` in the main Rails app, so it deploys and runs with the main app — no separate role, no separate droplet. The `mbuzz-shopify` droplet plan was dropped when the Shopify channel was killed. `mcp.mbuzz.co` is a DNS record + a kamal-proxy host alias pointing at the existing web droplet. |
| Tool naming | snake_case, `mbuzz_`-prefixed: `mbuzz_get_conversions` etc. | Decided 2026-05-15. snake_case is the 90%+ MCP convention; vendor prefix groups tools + avoids collisions; dots are discouraged. Dotted `mbuzz.spend.list` alternative rejected. |
| Tool granularity | 3 broad tools, not many narrow ones | An agent picks better from "get spend" than from 12 hyper-specific tools. Mirrors API shape. |
| Resource: account summary | Yes | Lets the agent prime itself in 1 read instead of N tool calls. |
| Per-tool scopes | No (v1) | The API key represents account-level access. Sub-scopes (read-only conversions only, e.g.) is a separate auth feature. |
| Rate limiting | Reuse whatever the JSON API has | Rate limiting is currently disabled globally per `base_controller.rb:9–12`; revisit when billing tiers ship — applies equally to API and MCP. |

---

## Out of Scope

- **Write tools** (e.g. `mbuzz_create_account`, `mbuzz_invite_user`). MCP v1 is read-only.
- **OAuth-based MCP auth** (third-party agent acts on behalf of a user). Bearer-key auth is enough until a partner asks for it.
- **Per-tool scoping** — granular permissions per tool. Defer until customers ask.
- **Streaming long results.** Pagination is fine for the data sizes we expose; true streaming is a future optimisation.
- **stdio transport / desktop-installable server.** Hosted-only in v1. Could ship a stdio variant later for power users.
- **Caching / response memoization at the MCP layer.** Underlying query services already cache where appropriate.
- **Custom AI assistant inside the mbuzz dashboard.** MCP is for connecting external assistants. An in-product assistant is a separate product.
- **Analytics on MCP usage.** Standard request logs are enough for v1; per-tool usage dashboards can come later.

---

## Open Questions

1. ~~**Hosting endpoint shape.**~~ **Resolved 2026-05-15:** `mcp.mbuzz.co` as a DNS + kamal-proxy host alias on the main web droplet. The MCP server is a route in the main Rails app, so it ships with the app — no separate role or droplet. The earlier `mbuzz-shopify` plan was dropped when the Shopify channel was killed.
2. ~~**Tool naming.**~~ **Resolved 2026-05-15:** snake_case, `mbuzz_`-prefixed (`mbuzz_get_conversions` / `mbuzz_get_funnel` / `mbuzz_get_spend`). Matches the dominant MCP convention; dotted form rejected (dots discouraged in tool names).
3. **Tool description length.** MCP clients vary in how they truncate descriptions. Keep under ~300 chars per tool, test in real clients in Phase 5.
4. ~~**Error semantics.**~~ **Resolved 2026-05-15 (Phase 2):** bad input (e.g. malformed date) returns an `MCP::Tool::Response` with `error: true` (`isError: true` on the wire) — a recoverable tool error the agent sees. Auth failures are transport-level 401s from the controller `before_action`.
5. ~~**Co-tenancy on `mbuzz-shopify`.**~~ **Moot — Shopify channel killed 2026-05-15, droplet decommissioned. MCP runs on the main web droplet as part of the main app.**

---

## Dependencies

`data_downloads_api_spec.md` — **satisfied 2026-05-12**. The three query services (`DataDownloads::ConversionsQueryService`, `DataDownloads::FunnelQueryService`, `DataDownloads::SpendQueryService`) and the matching controller endpoints are shipped. MCP tools delegate directly to those services; no further changes to the API surface are required to start this spec.
