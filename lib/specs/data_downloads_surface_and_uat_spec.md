# Data Downloads — Dashboard Surface + UAT

**Date:** 2026-05-14
**Priority:** P1
**Status:** Draft — active. UAT to be walked step-by-step against prod.
**Branch:** `feat/conversion-feedback`
**Depends on:** `old/data_downloads_api_spec.md` (shipped 2026-05-12), `old/dashboard_export_dropdown_spec.md` (shipped 2026-05-13). MCP row gated on `data_downloads_mcp_spec.md`.

---

## Summary

Yesterday we shipped three ways to get attribution data out of mbuzz: the dashboard CSV export, the JSON API (`/api/v1/data/{conversions,funnel,spend}`), and — soon — an MCP server. The Export dropdown today shows only the CSV row. Customers cannot discover the API from the place they already think about "getting my data out", and there is no docs page describing the API endpoints. The waitlist row that used to live there was deliberately removed when the API shipped because it pointed to nothing.

This spec adds API and MCP rows back to the dropdown (the API row points to a real destination now), creates a small docs page describing the three endpoints, and defines the UAT procedure that gates sign-off of both surfaces.

---

## Problem

1. **Discoverability.** The API exists on prod but has no dashboard entry point. A customer reading `data_downloads_api_spec.md` would know about it; a customer using the UI would not.
2. **No docs.** There is no `/docs/...` page that describes the data downloads endpoints. The spec is the only written source, and customer docs do not live in `lib/specs/`.
3. **MCP teaser.** The MCP server is the headline value of "your data in your AI assistant". We want the dropdown to show that it is coming, not surprise the customer with it when it ships.
4. **UAT gap.** The API was merged with green unit + controller tests but never exercised against prod with a real key. We need a written, repeatable UAT before declaring it customer-ready.

---

## Solution

### Dropdown shape

The Export dropdown at `app/views/dashboard/show.html.erb:77-103` shows three rows:

```
┌─ Export ▾ ─────────────────┐
│ Download CSV               │  ← submits the existing form (unchanged)
│ API                        │  ← links to /account/api_keys + docs link inline
│ MCP                  soon  │  ← greyed, non-interactive until MCP ships
└────────────────────────────┘
```

Row behaviour:

| Row | When the active tab is exportable (Conversions / Funnel / Spend) | When the active tab is Events |
|---|---|---|
| Download CSV | Form submit → `POST /dashboard/export` with `export_type=<tab>` (existing) | Hidden (existing) |
| API | Link → `account_api_keys_path` | Visible — Events is not exportable as CSV but the API is the same regardless of tab |
| MCP | Visible, greyed, `data-disabled="true"`, tooltip "Coming soon" | Same |

The entire dropdown trigger stays hidden on the Events tab today; with API/MCP being tab-agnostic the trigger now shows on Events too, with only API + MCP rows visible. Update `export_button_controller.js` to: keep the trigger visible on all tabs, but on Events hide the CSV row while keeping API + MCP visible.

### API row destination

Primary link: `account_api_keys_path` (`/account/api_keys`). When the customer lands there, a prominent inline link reads "See data downloads docs →" pointing to `/docs/data-downloads`. Two surfaces, but the API keys page is the practical landing (you need a key to use the API; the docs are reference once you have one).

### MCP row state

Until `data_downloads_mcp_spec.md` ships:
- Rendered as a div, not a link
- `text-gray-400 cursor-not-allowed`
- Right-aligned "soon" pill
- No href, no Stimulus action

When MCP ships, that spec updates this dropdown to make MCP a live link to its setup page (covered there, not duplicated here).

### Docs page

New page: `/docs/data-downloads`. Existing `docs#show` controller already handles `/docs/:page` and pulls partials from `app/views/docs/_<page>.html.erb`. Add:

- `app/views/docs/_data_downloads.html.erb` — three endpoints, query params, example responses, curl examples per endpoint
- Update `app/views/docs/show.html.erb` sidebar nav to include "Data Downloads" under the API section
- Authentication section reuses the existing `_authentication.html.erb` partial — link, do not duplicate

---

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Three rows in dropdown | Yes (CSV / API / MCP) | Customer mental model: "where do I get my data out?" — one menu, three answers. |
| Trigger button label | Stay "Export" | Customers know the word. Renaming creates a relearn cost for zero gain. |
| API row links to API keys page | Yes, with inline docs link from there | The key is the prerequisite. Without a key the docs are not actionable. |
| MCP row visible pre-ship | Yes, greyed with "soon" | Markets the upcoming feature in the right place. Hidden defeats the discoverability point. |
| Trigger visible on Events tab | Yes (with CSV row hidden) | API and MCP are tab-agnostic — they give back the same data regardless of which tab you opened. Hiding the trigger on Events orphans them. |
| New docs page | Yes, `/docs/data-downloads` | First customer-facing reference. Specs are not customer docs. |
| Spec for the dropdown change | New spec, not an amendment to the archived dropdown spec | Archived = shipped. New work goes in a new spec. |

---

## Key Files

| File | Purpose | Change |
|---|---|---|
| `app/views/dashboard/show.html.erb` | Export dropdown markup | Add API row (link), MCP row (greyed). Keep existing CSV row. |
| `app/javascript/controllers/export_button_controller.js` | Tab → row visibility | Show trigger on all tabs; hide CSV row (not whole trigger) on Events. |
| `app/views/accounts/api_keys/index.html.erb` | API keys page | Add inline "See data downloads docs →" link near the top |
| `app/views/docs/_data_downloads.html.erb` | Docs page partial | **Create** — three endpoints, params, curl examples |
| `app/views/docs/show.html.erb` | Docs sidebar | Add nav entry for "Data Downloads" under API section |
| `test/system/dashboard_export_dropdown_test.rb` | System test | **Create** if/when system tests are introduced; otherwise controller-level assertion on dropdown rendering |

No backend code changes — the API itself shipped 2026-05-12.

---

## All States

| State | Expected behaviour |
|---|---|
| Conversions tab, dropdown open | All three rows visible. CSV submits with `export_type=conversions`. |
| Funnel tab, dropdown open | All three rows visible. CSV submits with `export_type=funnel`. |
| Spend tab, dropdown open | All three rows visible. CSV submits with `export_type=spend`. |
| Events tab, dropdown open | Trigger visible. CSV row hidden. API + MCP rows visible. |
| Click API row | Navigates to `/account/api_keys` |
| API keys page | Shows inline link "See data downloads docs →" pointing to `/docs/data-downloads` |
| Click MCP row pre-ship | No navigation (no href). Cursor shows not-allowed. |
| `/docs/data-downloads` | Renders endpoints, params, curl examples |

---

## Acceptance Criteria

- [ ] Dropdown shows three rows on all four tabs (CSV hidden on Events; trigger always visible)
- [ ] API row navigates to `account_api_keys_path`
- [ ] API keys page contains a visible inline link to `/docs/data-downloads`
- [ ] `/docs/data-downloads` renders and includes: auth, three endpoints, query params, curl examples per endpoint
- [ ] MCP row visible, greyed, no href, "soon" pill, no nav on click
- [ ] All API UAT steps below sign off (live key + test key)
- [ ] MCP UAT walks when the MCP spec ships (deferred — see MCP spec)

---

## UAT Procedure — CSV (do this FIRST)

The CSV export changed substrate yesterday: local-disk on the jobs host → Active Storage on DO Spaces. Logs from 2026-05-13 23:52 UTC show `/dashboard/exports/exp_50nkDj2oRp21nU1GQvzgA9Je/download` returning `404` (not the pre-fix `MissingFile` 500). The 404 path in `Dashboard::ExportsController#download` is reached when `current_account.exports.completed.find(params[:id])` raises `RecordNotFound` — meaning the export is either not `:completed` (most likely `:failed`) or not in that account.

UAT walks: TDD-first new contract for the failure path → diagnose the live failure → confirm or update the fix → re-run download end-to-end on all three exportable tabs.

### TDD post-mortem — why didn't the test suite catch this?

Honest answer:

1. Tests use the `:test` Active Storage service (local Disk, scoped by PID). Production uses `:digitalocean` (S3). Any S3-specific bug (credential shape, signing, region, bucket existence, blob-key collision in real S3) ships unverified by the unit suite.
2. **No test asserts that a `:failed` export shows the user a helpful state.** The current `Dashboard::ExportsController#download` returns `head :not_found` for any not-`:completed` export — pending, processing, *failed*, wrong account — all bare 404. A real `ExportJob` exception leaves the customer with no information.
3. No deploy-time smoke that actually fetches a real signed URL from real Spaces. Belongs in a deploy task, not `bin/rails test`.

### New contract (RED tests, then code)

Smallest UX-improving fix with TDD: a failed / in-flight export should redirect back to the status page where the existing `_failed.html.erb` / `_processing_status.html.erb` partials already render the right state. Bare 404 stays only for genuinely missing IDs.

- [x] **C0.1** RED → GREEN: `download for :failed export redirects to status page` (`test/controllers/dashboard/exports_controller_test.rb`)
- [x] **C0.2** RED → GREEN: `download for :pending export redirects to status page` (replaces the prior "returns 404 for pending export" test)
- [x] **C0.3** RED → GREEN: `download for :processing export redirects to status page`
- [x] **C0.4** RED → GREEN: `download_url carries attachment disposition and filename` (`test/models/export_test.rb`) — decodes the `:test` Disk service's signed payload so the assertion holds across services
- [x] **C0.5** GREEN: `Dashboard::ExportsController#download` now `find_by_prefix_id!` outside the `:completed` scope and branches on status — non-completed redirects to the status page where `_failed.html.erb` / `_processing_status.html.erb` already render the right state
- [x] **C0.6** Full suite green (`3886 runs, 9296 assertions, 0 failures, 0 errors, 0 skips`)
- [x] **C0.7** Commit RED → GREEN — `fix(export): redirect non-completed downloads to status page so failed exports surface the failure` (`975a960`)

### Second TDD round — status field is unreliable, pivot to `csv.attached?` as the truth signal

Discovered during C1.1 UAT (2026-05-13 prod console): `exp_50nkDj2oRp21nU1GQvzgA9Je` has `status="processing"` but `csv.attached?=true`, `completed_at` and `expires_at` set, and `filename` populated. The timestamps prove `complete_export` set status to `:completed` at 23:51:24.398, then ~180ms later something updated only `status` (back to `processing`). The only code path that calls `processing!` is `Dashboard::ExportJob#perform`'s first line — so the job ran twice. Consistent with the 2026-04-22 Solid Queue redelivery incident (`lib/specs/job_isolation_and_invalidation_fix_spec.md`).

Consequence: `status` flaps. The customer's Show view renders "Preparing your export" forever because the conditional gates on `@export.completed?`, and the first turbo broadcast has already fired so there is nothing to push to make the page change. Bytes are sitting in Spaces, unreachable.

Pivot: `csv.attached?` is the reliable signal. Use that as the gate; treat `status` as advisory display state, not source of truth. Also harden the job so a redelivery is a no-op.

- [x] **C0.8** RED → GREEN: `download serves the file when csv is attached regardless of status (flap defense)` + same for `:failed` status with blob attached
- [x] **C0.9** RED → GREEN: `show renders download button when blob is attached regardless of status`
- [x] **C0.10** RED → GREEN: `perform is a no-op for an already-:completed export` + `perform does not broadcast for an already-:completed export`
- [x] **C0.11** GREEN: `Dashboard::ExportsController#download` gates on `csv.attached?` (no longer on `completed?`); `dashboard/exports/show.html.erb` branches on `csv.attached? && !expired?` first; `Dashboard::ExportJob#perform` returns early when `@export.completed?`. The prior "410 when blob is missing" test rewritten to assert the new contract (redirect to status page rather than 410).
- [x] **C0.12** Full suite green (`3892 runs, 9309 assertions, 0 failures, 0 errors, 0 skips`); commit pending

Deferred (recorded so we don't forget):

- Deploy-time smoke task that creates → downloads → verifies bytes against prod Spaces. Belongs in `lib/tasks/`, runs post-deploy via Kamal hook.
- A "Try again" button on `_failed.html.erb` that creates a new export with the same `filter_params` — separate spec since it needs a `retries` count to avoid infinite loops.
- Persist `failure_reason` on the Export so `_failed.html.erb` can show *why* it failed. Requires a migration; separate spec.
- Root-cause fix for Solid Queue redelivery on the `:default` queue — covered by `lib/specs/job_isolation_and_invalidation_fix_spec.md` (not on this branch). The idempotency guard here is defense in depth, not the cure.

### Diagnose

- [x] **C1.1** Read the failing export's state on prod (2026-05-14 morning)
  ```ruby
  e = Export.find("exp_50nkDj2oRp21nU1GQvzgA9Je")
  [e&.status, e&.csv&.attached?, e&.completed_at, e&.expires_at, e&.account&.prefix_id, e&.filename]
  ```

  **Result:**
  ```
  ["processing",
   true,
   2026-05-13 23:51:24.398575 UTC,
   2026-05-14 00:51:24.398588 UTC,
   "acct_j4y1qlbVAMlkQHbwp0BWLYGz",
   "mbuzz-conversions-2026-05-13.csv"]
  updated_at: 2026-05-13 23:51:24.580041 UTC
  ```

  **Read:** the blob is in Spaces (`csv.attached?` true) and `complete_export` did run (`completed_at` + `expires_at` + `filename` all set). Status flipped from `:completed` → `:processing` ~180ms after completion, which only `Dashboard::ExportJob#perform`'s first line does (`@export.processing!`). The job ran twice. Cross-host upload itself worked. The pivot to `csv.attached?` as the source of truth (second TDD round above) addresses the resulting UI lockup. Root-cause for the redelivery sits with `job_isolation_and_invalidation_fix_spec.md`.

- [ ] **C1.2** If status is `:failed`, find the matching `ExportJob` exception
  - Tail SolidErrors / log around 2026-05-13 23:51-52 UTC for `Dashboard::ExportJob` failure
  - Common suspects: missing `do_spaces` credential keys on prod, region/endpoint mismatch, Active Storage tables not yet migrated, `attach_csv` raising on `key:` collision
  
  **Exception class + message:** _(fill in)_

- [ ] **C1.3** If status is `:pending` / `:processing`: the job is stuck or queue is paused. Check Solid Queue dashboard for queued / failed jobs for `Dashboard::ExportJob`. Note that queues were paused per the 2026-04-22 outage remediation — `lib/specs/job_isolation_and_invalidation_fix_spec.md` is the gate.

  **Queue state:** _(fill in)_

- [ ] **C1.4** If status is `:completed` but the user got 404: the export does not belong to the current account at request time. Check whether the user switched accounts between create and download.

  **Account match:** _(fill in)_

### Fix (decided once C1.1-C1.4 is filled in)

Decision tree — only one branch applies:

- **Branch F-FAIL** (status `:failed`, real exception captured):
  - Reproduce locally with the same params + a live-shaped fixture, get the test red
  - Patch the offending code path (most likely candidates: `Dashboard::ExportJob#attach_csv` if `key:` collides; `config/storage.yml` if `do_spaces` creds are partial on prod; ApplicationStorage host wiring)
  - Add a regression test under `test/jobs/dashboard/export_job_test.rb` that covers the failure mode
  - Verify green
  
- **Branch F-STUCK** (status `:pending`/`:processing` with queues alive): no code change — re-queue or unblock the Solid Queue worker. If queues are paused per the 2026-04-22 remediation, this UAT pauses until that spec ships.

- **Branch F-ACCOUNT** (status `:completed`, account mismatch): expected; no fix. UI bug if the dashboard let the user reach a download URL for a different account.

- [ ] **C2.1** Record which branch + the actual change (commit SHA if code)
- [ ] **C2.2** Local tests green for the regression
- [ ] **C2.3** Deploy to prod (Kamal)

### Re-run end-to-end (each exportable tab)

For each of `conversions`, `funnel`, `spend`:

- [x] **C3.1 — Conversions** Signed off 2026-05-14: status page rendered, Download served the CSV from Spaces.

- [ ] **C3.2 — Funnel** Deferred. Same code path as Conversions through the controller + job — the only delta is `FunnelCsvExportService`. Re-run when convenient.

- [ ] **C3.3 — Spend** Deferred. Same as C3.2; only delta is `SpendCsvExportService`.

### Cross-host substrate proof

- [ ] **C4.1** The download URL the browser actually hits is a `*.digitaloceanspaces.com` signed URL (the controller `redirect_to`s to it). Confirm by watching the network tab — first hop `/dashboard/exports/<id>/download` returns 302, second hop is Spaces.
- [ ] **C4.2** A second click on the same Download button within the 5-minute window still works (signed URL valid). After 1 hour, the dashboard "Download" link returns `410 Gone` (`export.expired?` branch). Don't need to wait an hour — read it off the controller code.

### Sign-off

- [ ] **C5.1** All three CSV downloads worked end-to-end against prod
- [ ] **C5.2** SolidErrors shows no `MissingFile` and no `ExportJob` exceptions from the UAT session
- [ ] **C5.3** Move on to API UAT below

---

## UAT Procedure — API

We walk these step by step against prod (`https://mbuzz.co`). Each step has an "expect" line. We tick the box and record any deviation inline. Replace `<TEST_KEY>` and `<LIVE_KEY>` with real keys before starting; do not commit them. Capture `total_count` numbers — they are the cross-checks against the dashboard.

### Pre-flight

- [ ] **A0.1** Create a test API key from `/account/api_keys` if one does not already exist. Capture it locally only (1Password / scratch buffer, never in spec). Expect: key starts with `sk_test_`.
- [ ] **A0.2** Create a live API key the same way. Expect: starts with `sk_live_`.
- [ ] **A0.3** Note current dashboard `total_count` for conversions (default 30-day window), funnel records, and spend rows on each tab. We will compare API totals against these.

### Auth boundary

- [ ] **A1.1** No header → 401
  ```bash
  curl -i https://mbuzz.co/api/v1/data/conversions
  ```
  Expect: `401`, body `{"error":"Missing Authorization header"}` (or equivalent — record actual).

- [ ] **A1.2** Bogus key → 401
  ```bash
  curl -i -H "Authorization: Bearer sk_test_fake_definitely_not_real" \
    https://mbuzz.co/api/v1/data/conversions
  ```
  Expect: `401`, body matches "invalid or expired" wording from `ApiKeys::AuthenticationService`.

- [ ] **A1.3** Wrong scheme → 401
  ```bash
  curl -i -H "Authorization: Basic <base64>" https://mbuzz.co/api/v1/data/conversions
  ```
  Expect: `401`.

### Conversions endpoint

- [ ] **A2.1** Default window, test key, page 1
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions" | jq '{meta: .meta, sample: .data[0]}'
  ```
  Expect: 200; `meta` has `total_count`, `page=1`, `per_page=100`, `total_pages`; `sample` row has the columns from spec (date, type, name, channel, credit, revenue, revenue_credit, attribution_model, etc.).

- [ ] **A2.2** Page 2 returns disjoint rows
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?per_page=5&page=1" | jq '.data | map(.date)'
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?per_page=5&page=2" | jq '.data | map(.date)'
  ```
  Expect: lengths 5 each (or 5 + remainder); rows differ.

- [ ] **A2.3** `per_page` clamping
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?per_page=99999" | jq '.meta.per_page, (.data | length)'
  ```
  Expect: `per_page` clamped to `1000`, `data.length <= 1000`.

  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?per_page=0" | jq '.meta.per_page'
  ```
  Expect: clamped to `1`.

- [ ] **A2.4** Custom date range
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?start_date=2026-04-01&end_date=2026-05-14&per_page=5" \
    | jq '.meta, ([.data[].date] | min, max)'
  ```
  Expect: all `date` values inside `[2026-04-01, 2026-05-14]`.

- [ ] **A2.5** Channel filter
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?channels[]=paid_search&channels[]=direct&per_page=20" \
    | jq '[.data[].channel] | unique'
  ```
  Expect: subset of `["paid_search","direct"]` only.

- [ ] **A2.6** Test vs live data isolation
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?per_page=1" | jq '.meta.total_count'
  curl -s -H "Authorization: Bearer <LIVE_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?per_page=1" | jq '.meta.total_count'
  ```
  Expect: numbers differ (unless the account has zero data on one side); both match the corresponding dashboard view-mode total.

### Funnel endpoint

- [ ] **A3.1** Default window, sample row
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/funnel?per_page=5" | jq '.meta, .data[0:3]'
  ```
  Expect: rows of `type` in `{visit, event, conversion}`; mixed types present if data spans them.

- [ ] **A3.2** Funnel filter narrows results
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/funnel?funnel=sales&per_page=20" \
    | jq '[.data[].funnel] | unique'
  ```
  Expect: `["sales"]` or `[null, "sales"]` only (visits may not carry a funnel). Record actual.

- [ ] **A3.3** Channel filter on funnel
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/funnel?channels[]=organic_search&per_page=20" \
    | jq '[.data[].channel] | unique'
  ```
  Expect: `["organic_search"]` only.

### Spend endpoint

- [ ] **A4.1** Default window, sample row
  ```bash
  curl -s -H "Authorization: Bearer <LIVE_KEY>" \
    "https://mbuzz.co/api/v1/data/spend?per_page=5" | jq '.meta, .data[0]'
  ```
  Expect: 200; row has `spend_date`, `channel`, `platform`, `campaign_name`, `spend` (number in major units, not micros), `currency`, `metadata` (object or null — not a string).

- [ ] **A4.2** Spend is in major units, not micros
  Inspect `.data[*].spend`. Expect: values look like dollars/cents (e.g. `12.34`), not millions (e.g. `12340000`).

- [ ] **A4.3** `metadata` is a JSON object
  ```bash
  curl -s -H "Authorization: Bearer <LIVE_KEY>" \
    "https://mbuzz.co/api/v1/data/spend?per_page=5" \
    | jq '.data[0].metadata | type'
  ```
  Expect: `"object"` or `"null"`. Never `"string"`.

- [ ] **A4.4** Channel filter
  ```bash
  curl -s -H "Authorization: Bearer <LIVE_KEY>" \
    "https://mbuzz.co/api/v1/data/spend?channels[]=paid_search&per_page=20" \
    | jq '[.data[].channel] | unique'
  ```
  Expect: `["paid_search"]` only.

### Cross-checks against the dashboard

- [ ] **A5.1** Conversions total reconciles
  - Dashboard → Conversions tab, default 30 days, no filters → note `total_count` of attribution credit rows
  - API → `/api/v1/data/conversions` → `.meta.total_count`
  - Expect: equal. If different, capture both numbers, the date range, and any filter applied.
- [ ] **A5.2** Funnel total reconciles same way (Funnel tab vs `/api/v1/data/funnel`)
- [ ] **A5.3** Spend total reconciles same way (Spend tab vs `/api/v1/data/spend`)

### Edge / negative

- [ ] **A6.1** Revoked key → 401
  Revoke the live key via the dashboard, then re-curl `/api/v1/data/conversions`. Expect: 401 with revocation wording. Then unrevoke (or rotate) before continuing.
- [ ] **A6.2** Page beyond range
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?page=999" | jq '.meta, (.data | length)'
  ```
  Expect: `data` length `0`, `meta.page` `999`, no error.
- [ ] **A6.3** Bad date format
  ```bash
  curl -i -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?start_date=banana&end_date=2026-05-14"
  ```
  Expect (per shipped behaviour): falls back to default 30-day window, 200 response — not 400. This deviates from the original draft and is recorded in `old/data_downloads_api_spec.md` "Shipped Deviations".
- [ ] **A6.4** Invalid channel ignored
  ```bash
  curl -s -H "Authorization: Bearer <TEST_KEY>" \
    "https://mbuzz.co/api/v1/data/conversions?channels[]=fake_channel&per_page=5" \
    | jq '.meta.total_count'
  ```
  Expect: behaves as if no channel filter applied (unknown channel ignored, not error).

### Recording results

For each box above: tick if it matched expectation. If it did not, capture:
- Step ID (e.g. `A2.3`)
- Command actually run
- Response received (status, body excerpt)
- What was expected vs what we got

We append a "UAT Results" section to this spec at the end of the session with anything that was off, the fix, and a re-test note.

---

## UAT Results — 2026-05-14 session

Ran `~/Downloads/mbuzz_api_uat.sh` against `mbuzz.co` with a `sk_live_*` key.

### Passes (14)

A1.1, A1.2, A1.3 (auth boundary). A2.1 (default conversions), A2.3 (per_page clamping high + low), A2.4 status, A2.5 channel filter, A3.1 status, A3.2 status, A3.3 channel filter, A4.1 status, A4.3 metadata-is-object, A4.4 channel filter, A6.4 invalid channel ignored.

### Script flaws (not API bugs — to fix in `~/Downloads/mbuzz_api_uat.sh`)

- **A2.2** "page 2 disjoint" compared only `date` arrays. With 207k+ rows on the same date under `ORDER BY converted_at ASC`, both pages show the same five dates. Tighten the comparison to the full row contents (or to a unique-enough subset of fields).
- **A2.4** "date range observed" min/max sampled only 5 rows. First 5 rows by `converted_at ASC` in a six-week window are all on day 1. Either widen `per_page` or sort by random or check `meta.total_count` against an independent count.
- **A6.2** "page beyond range" used `page=999`, but `total_pages` from A2.1 was 2074. 999 is in range. Use a clearly out-of-bounds page like `page=99999`.

### Real bugs found + fixed (TDD round, 2026-05-14)

- [x] **A6.3** Bad date format returned **500** (`Date.parse("banana")` raised `Date::Error` from inside `Dashboard::DateRangeParser`, unhandled). **Fixed**: `Api::V1::DataController` now declares `rescue_from Date::Error, with: :render_bad_date_format` and returns `400 { "error": "Invalid date format. Use YYYY-MM-DD." }`. Four new controller tests cover invalid start_date on all three endpoints + invalid end_date on conversions.
- [x] **A3.2** Funnel filter was incomplete — passed only to `EventsScope`. **Fixed (strict)**: `Dashboard::Scopes::ConversionsScope` gains a `funnel:` kwarg + `apply_funnel` step; `DataDownloads::FunnelQueryService` passes funnel through to it and returns `[]` for visits + sets `visit_count` to 0 when a funnel filter is set. Three new service tests assert: visits excluded, events narrowed, conversions narrowed.
- [x] **Spec-content fix**: `old/data_downloads_api_spec.md` "Shipped Deviations" line saying bad dates fall back to default 30d was wrong (the shipped code 500'd, not 200'd). Corrected to reflect the 400 contract.

### Cross-checks (A5) — all pass, verified via Rails console

Console queries replicate the same scopes the API uses. All three reconcile within expected ingest drift.

| Endpoint | API total_count (initial) | Console count | API total_count (recheck) | Status |
|---|---|---|---|---|
| Conversions (default 30d, all channels) | 207,305 | 207,305 | 207,337 (+32 in ~5min) | ✓ exact match at A5.1, drift from continued ingest |
| Funnel (default 30d, all channels) | 102,215 | 102,319 (+104) | 102,350 (+31 from console) | ✓ monotonic growth = ingest drift, not divergence |
| Spend (default 30d, all channels) | 3,826 | 3,826 | 3,826 | ✓ exact match, stable dataset |

Console queries used:

```ruby
account = Account.find(2)  # acct_j4y1qlbVAMlkQHbwp0BWLYGz

# A5.1
Dashboard::Scopes::FilteredCreditsScope.new(
  account: account,
  models: account.attribution_models.active,
  date_range: Dashboard::DateRangeParser.new("30d"),
  channels: Channels::ALL,
  test_mode: false
).call.count

# A5.2
parser = Dashboard::DateRangeParser.new("30d")
s = Dashboard::Scopes::SessionsScope.new(account: account, date_range: parser, channels: Channels::ALL, test_mode: false).call.count
e = Dashboard::Scopes::EventsScope.new(account: account, date_range: parser, channels: Channels::ALL, test_mode: false, funnel: nil).call.count
c = Dashboard::Scopes::ConversionsScope.new(account: account, date_range: parser, channels: Channels::ALL, test_mode: false).call.count
{ sessions: s, events: e, conversions: c, total: s + e + c }
# => {sessions: 91506, events: 8864, conversions: 1949, total: 102319}

# A5.3
account.ad_spend_records
  .where(spend_date: parser.start_date..parser.end_date, is_test: false)
  .count
```

The `~/Downloads/mbuzz_api_uat.sh` script gained a `totals` mode for drift comparisons:

```bash
bash ~/Downloads/mbuzz_api_uat.sh totals
```

### Manual + interactive (pending)

- **A2.6** test vs live isolation — needs a `sk_test_*` key; not generated yet.
- **A6.1** revoked-key 401 — interactive; revoke the key, re-run, restore.

---

## UAT Procedure — MCP

Placeholder. The MCP spec (`data_downloads_mcp_spec.md`) is still draft. Its Phase 5 "Manual verification" section will mirror this structure (auth boundary, tool calls, resource reads, cross-checks against the dashboard) once the MCP server exists. Until then this section reads:

- [ ] **M0** MCP UAT script written into `data_downloads_mcp_spec.md` Phase 5 — **blocked on MCP shipping**
- [ ] **M1** MCP UAT walked end-to-end — **blocked on M0**

When MCP ships, that spec's Phase 5 supersedes this placeholder. The dropdown row toggles from greyed-with-soon to a live link as part of the MCP ship checklist.

---

## Out of Scope

- Rate limiting on `/api/v1/data/*` (rate limiting is globally disabled per `Api::V1::BaseController:9-12`; revisit when billing tiers ship)
- Streaming / cursor pagination (offset is fine for bounded date ranges)
- API SDKs (curl + raw HTTP is the supported surface today)
- Webhook delivery of data downloads
- Per-field column selection
- The MCP setup page itself (lives in the MCP spec)
