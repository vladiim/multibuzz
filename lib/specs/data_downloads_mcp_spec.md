# Data Downloads MCP Server Specification

**Date:** 2026-05-13
**Priority:** P1
**Status:** Draft — ready to start (dependency satisfied 2026-05-12)
**Branch:** `feat/data-downloads-mcp` (will branch off `feat/conversion-feedback` once that ships, or off `main` post-merge)
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

A streamable-HTTP MCP server hosted at `mcp.mbuzz.co` (or `mbuzz.co/mcp`, TBD on hosting model), authenticated by the same API key the JSON API uses. The server exposes three MCP **tools**, each a thin shim over a JSON endpoint:

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

Streamable HTTP is the post-2025 successor to SSE in the MCP spec. Bearer auth in the HTTP header, server-sent events for streaming responses if needed.

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
    → Mcp::Server (FastMcp-style Rack app)
      → authenticate via ApiKeys::AuthenticationService
      → dispatch tool call
        → Data::ConversionsQueryService / FunnelQueryService / SpendQueryService
          → existing scopes
          → JSON result → MCP tool_result content
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `Gemfile` | Add `fast_mcp` (or equivalent Ruby MCP server gem) | **Edit** |
| `app/mcp/server.rb` | MCP server Rack app | **Create** |
| `app/mcp/tools/get_conversions.rb` | Conversions tool — delegates to `DataDownloads::ConversionsQueryService` | **Create** |
| `app/mcp/tools/get_funnel.rb` | Funnel tool — delegates to `DataDownloads::FunnelQueryService` | **Create** |
| `app/mcp/tools/get_spend.rb` | Spend tool — delegates to `DataDownloads::SpendQueryService` | **Create** |
| `app/mcp/resources/account_summary.rb` | Account summary resource | **Create** |
| `app/mcp/authentication.rb` | Bearer-token middleware → reuses `ApiKeys::AuthenticationService` | **Create** |
| `config/routes.rb` | Mount MCP server at `/mcp` | **Edit** |
| `app/controllers/api/v1/base_controller.rb` | No change — MCP doesn't go through it (separate auth surface) | unchanged |
| `app/services/data_downloads/{conversions,funnel,spend}_query_service.rb` | Reused from API spec (shipped 2026-05-12) | unchanged |
| `app/views/docs/mcp.html.erb` | Customer-facing MCP setup docs | **Create** |
| `app/views/accounts/api_keys/show.html.erb` | Add "Use this key with MCP" block with the URL + setup snippet | **Edit** |

### Choice of MCP Library

| Option | Status | Notes |
|---|---|---|
| `fast_mcp` (Ruby) | Active, maintained | Closest to "Rails-native MCP server" — Rack-mountable, supports streamable HTTP. Default choice. |
| Roll our own | High cost | MCP protocol is non-trivial (handshake, capability negotiation, content types). No reason. |
| Node sidecar | Possible | Would mean an extra service to operate. Avoid unless `fast_mcp` proves inadequate. |

Decision needed: confirm `fast_mcp` (or whichever Ruby MCP library has the best streamable-HTTP support at implementation time) handles streamable HTTP transport. If not, reconsider Node sidecar.

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

### Phase 1: Auth + transport foundation

- [ ] **1.1** Add MCP gem to `Gemfile`; `bundle install`; commit
- [ ] **1.2** Spike: confirm gem supports streamable HTTP with custom auth middleware. If not, decide alternative before continuing.
- [ ] **1.3** Create `app/mcp/authentication.rb` — Rack-level bearer-token check, calls `ApiKeys::AuthenticationService`, sets a thread-local or env-keyed account on the request
- [ ] **1.4** Mount the MCP server at `/mcp` in `config/routes.rb`
- [ ] **1.5** Test: `curl` with valid key → 200 handshake; without key → 401; with revoked key → 401
- [ ] **1.6** Confirm `Api::V1::BaseController` is untouched and the MCP auth path is independent

### Phase 2: Tool surface

- [ ] **2.1** Create `app/mcp/tools/get_conversions.rb` — delegates to `Data::ConversionsQueryService` (built in API spec)
- [ ] **2.2** Test: tool call returns `data` + `meta`; rejects bad date format; respects pagination
- [ ] **2.3** Create `app/mcp/tools/get_funnel.rb` + test
- [ ] **2.4** Create `app/mcp/tools/get_spend.rb` + test — delegates to `DataDownloads::SpendQueryService` (already shipped)
- [ ] **2.5** Each tool's `description` reviewed for "would the agent pick this correctly" — short, intent-focused
- [ ] **2.6** Cross-account isolation test per tool

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
| Transport | Streamable HTTP | We host. Customer pastes URL + key, no local server. |
| Auth | Existing API keys | Zero new credential surface. Account scoping, env, revocation, logging — already built. |
| Library | `fast_mcp` (Ruby) | Rails-native, Rack-mountable. Confirm streamable HTTP support in Phase 1.2. |
| Hosting endpoint | `/mcp` mounted on the main app | Single deployment surface; same Kamal pipeline. Re-evaluate if traffic patterns warrant a separate service. |
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

1. **Hosting endpoint shape.** `/mcp` mounted on the main Rails app, or `mcp.mbuzz.co` subdomain? Subdomain is cleaner for client setup but adds Kamal + DNS work. Resolve before Phase 4.
2. **Tool naming.** `mbuzz_get_spend` reads cleanly to humans but verbose to agents. Alternative: `mbuzz.spend.list` (dotted). Confirm with `fast_mcp` conventions before Phase 2.
3. **Tool description length.** MCP clients vary in how they truncate descriptions. Keep under ~300 chars per tool, test in real clients in Phase 5.
4. **Error semantics.** MCP supports `is_error: true` on tool results vs. transport-level errors. Confirm we use the right one for "bad date range" vs "auth failure".

---

## Dependencies

`data_downloads_api_spec.md` — **satisfied 2026-05-12**. The three query services (`DataDownloads::ConversionsQueryService`, `DataDownloads::FunnelQueryService`, `DataDownloads::SpendQueryService`) and the matching controller endpoints are shipped. MCP tools delegate directly to those services; no further changes to the API surface are required to start this spec.
