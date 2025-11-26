### Revised High-Level Epic: MVP for Multibuzz SaaS Rails App and Client Gem

#### Epic Overview
As a developer building Multibuzz, I want to create an MVP SaaS Rails app that serves as the central backend for marketing attribution, along with a client Rails gem that acts as a wrapper for integration into users' apps, so that client apps can easily send tracking data to the SaaS service for processing and exports.

- **Scope**: The SaaS app (Rails backend) handles core logic: storing events, computing attributions/revenue, and providing API/ETL exports. The gem is a lightweight client wrapper: installs in users' Rails apps, captures events/visitors server-side, and sends to the SaaS API. Demo/test by implementing the gem in a separate client app (e.g., your existing business app or a dummy one). Basic homepage on SaaS app; all admin/features behind login.
- **Approach to SaaS App vs. Gem**: Build in tandem, starting with the SaaS app for core API/logic, then develop the gem to interact with it. Use a separate client app repo for testing the gem (e.g., `rails new mbuzz-client --database=postgresql`). This ensures the gem wraps client-side tracking and pushes to the SaaS backend without embedding heavy logic.
- **Tech Stack**: Rails (for SaaS app and gem), PostgreSQL (central DB for SaaS), Redis (optional for queuing). Minitest for testing. TailwindCSS for basic SaaS homepage/login views. Solid architecture (e.g., Solid Queue for jobs, Solid Cache for perf). Hotwire/Turbo/Stimulus for light interactivity in SaaS admin. Kamal for deployment of SaaS app.
- **Assumptions**: SaaS app requires login (rollout) for everything except homepage. Client gem handles server-side tracking only (no JS). Rule-based attribution in SaaS; no ML. Will have account multi-tennancy. Client app simulates a SaaS SME integrating the gem.

#### Key Milestones and Features (High-Level Stories)
Organized by phase. Estimate: 2-4 weeks for MVP.

1. **Setup and Infrastructure (Foundation)**
   - Generate SaaS app: Use `rails new multibuzz-saas --database=postgresql --css=tailwind`. Add basic homepage (static, Tailwind-styled: "Multibuzz – No-Frills Backend Attribution SaaS").
   - Add simple authentication and authorisation
   - Incorporate Solid: Add Solid Queue/Cache for jobs/caching; configure initializer.
   - API foundation: Set up API namespace (e.g., `/api/v1/events` for ingestion, `/api/v1/attributions` for queries).
   - Frontend basics: Hotwire/Turbo/Stimulus for minimal admin interactivity (e.g., dynamic lists).
   - Gem skeleton: `bundle gem mbuzz`. Make it a client library (not engine initially); include HTTP client (e.g., Faraday) for API calls to SaaS.
   - Client app setup: `rails new mbuzz-client --database=postgresql` (minimal, for gem testing).
   - Testing/Deploy: Minitest for all; Kamal config for SaaS app deploy.

2. **Visitor and Session Management (Identification in Client, Storage in SaaS)**
   - In SaaS app: Models/tables for visitors (hashed IDs, sessions); API endpoint to receive/validate IDs.
   - In gem: Middleware to generate/set visitor IDs (e.g., hash-based); config for API key/endpoint (initializer: `Mbuzz.configure { |config| config.api_url = 'https://mbuzz.co/api', config.api_key = 'xyz' }`). Send IDs to SaaS via POST.
   - Test in client app: Install gem, add middleware; simulate requests to verify data hits SaaS DB (view via logged-in admin).

3. **Event Tracking (Capture in Client, Ingestion in SaaS)**
   - In SaaS app: `events` model (JSONB props); API to receive events; Solid Queue for async processing/storage.
   - In gem: Extend middleware for auto-logging (e.g., page views); helper for customs (`mbuzz_track(:signup, properties: {})`). Queue and send batches to SaaS API.
   - Admin view in SaaS: Behind login, list events (Tailwind table; Stimulus for sorting, Turbo for updates).

4. **Attribution Computation (Core in SaaS)**
   - In SaaS app: Service/jobs for models (e.g., linear); compute on received events via Solid Queue. Store in `attributions` table; include revenue calcs (e.g., ARR).
   - In gem: No compute—query SaaS API for results (e.g., `Mbuzz::Attribution.fetch(model: :linear, visitor_id: id)`).
   - Test: From client app, track events; query attributions via gem (view in SaaS admin).

5. **ETL Exports (Output from SaaS)**
   - In SaaS app: API for JSON/CSV; web views (behind login) for downloads. ETL integrations (e.g., to Snowflake via gems); Hotwire for progress.
   - In gem: Wrappers to fetch exports (e.g., `Multibuzz::Export.download(format: :csv)`).
   - Dashboard in SaaS: Behind login, trigger/view exports (Turbo streams for status).

6. **Polish and Deployment (MVP Closeout)**
   - Gem packaging: README with install/integration guide; publish to RubyGems (private first).
   - Full integration: Install gem in client app; verify end-to-end (client track → SaaS process → export via gem/SaaS admin).
   - Security/Privacy: API auth, hashing; retention in SaaS.
   - Deployment: Kamal for SaaS app; client app local for testing.

#### Success Criteria
- Gem installs in client app, tracks/sends to SaaS seamlessly.
- SaaS app processes data, computes attributions, and exports (accessible via API/gem or logged-in views).
- End-to-end flow validated with client app as "user."

This flips the focus: SaaS app as central service, gem as client wrapper. Next steps could include API specs or Phase 1 code.
