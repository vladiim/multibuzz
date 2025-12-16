# SDK Integration Testing Framework

## Overview

End-to-end integration tests for mbuzz SDKs (Ruby, Node.js) using **Capybara + Playwright driver** (Ruby tests with Playwright browser automation).

**Key features:**
- Ruby test files using Capybara DSL (familiar to Rails devs)
- Playwright driver for reliable browser automation
- Lives in `sdk_integration_tests/` at project root (completely isolated from Rails test runner)
- Can test all SDKs or one at a time

---

## CRITICAL: Complete Isolation

**This infrastructure MUST NOT impact the main app in ANY way:**

- [x] **Separate directory**: `sdk_integration_tests/` at project root (NOT inside `test/`)
- [x] **Separate Gemfile**: `sdk_integration_tests/Gemfile` - NOT added to main `Gemfile`
- [x] **Separate bundle**: Run `bundle install` inside `sdk_integration_tests/` only
- [x] **Separate node_modules**: Each test app has its own `package.json` and `node_modules/`
- [x] **No main app dependencies**: capybara-playwright-driver is NOT in the main Gemfile
- [x] **Verification endpoint**: Only controller added to main app (one file, gated to test keys)
- [x] **No gems installed globally**: All gems isolated to `sdk_integration_tests/`
- [x] **Rails test isolation**: `rails test` does NOT load SDK integration tests

**The only change to the main multibuzz app:**
1. `app/controllers/api/v1/test_verification_controller.rb` (new file)
2. One line in `config/routes.rb` (add test namespace route)

**Everything else is completely isolated in `sdk_integration_tests/`.**

**Why outside `test/`?** Rails' test runner automatically loads all `*_test.rb` files under `test/`. By placing SDK integration tests at the project root, we ensure `rails test` never tries to load them (which would fail due to missing gems like capybara-playwright-driver).

---

## Directory Structure

```
/Users/vlad/code/multibuzz/
  sdk_integration_tests/        # NOTE: At project root, NOT inside test/
    README.md
    Gemfile                    # capybara, capybara-playwright-driver
    test_helper.rb             # Base class, Capybara setup

    scenarios/                  # Shared test scenarios (Ruby)
      first_visit_test.rb
      returning_visit_test.rb
      event_tracking_test.rb
      identify_test.rb
      conversion_test.rb
      utm_capture_test.rb
      concurrent_test.rb

    helpers/
      verification_helper.rb   # Query verification endpoint
      test_config.rb           # Env vars, URLs, ports

    apps/
      mbuzz_ruby_testapp/      # Sinatra + mbuzz-ruby (port 4001)
        Gemfile
        config.ru
        app.rb
        views/index.erb

      mbuzz_node_testapp/      # Express + mbuzz-node (port 4002)
        package.json
        server.ts
```

**Naming convention:** `mbuzz_{sdk}_testapp`

**Port assignments:**
| SDK | Port |
|-----|------|
| Ruby | 4001 |
| Node | 4002 |
| Python (future) | 4003 |
| PHP (future) | 4004 |

---

## Test Setup (Capybara + Playwright)

**File:** `sdk_integration_tests/Gemfile`

```ruby
source "https://rubygems.org"

gem "minitest"
gem "capybara"
gem "capybara-playwright-driver"
gem "rake"
```

**File:** `sdk_integration_tests/test_helper.rb`

```ruby
require "minitest/autorun"
require "capybara/minitest"
require "capybara-playwright-driver"

# Playwright setup
Capybara.register_driver :playwright do |app|
  Capybara::Playwright::Driver.new(app, browser_type: :chromium, headless: true)
end

Capybara.default_driver = :playwright
Capybara.javascript_driver = :playwright

class SdkIntegrationTest < Minitest::Test
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  def setup
    # Set base URL based on SDK being tested
    Capybara.app_host = sdk_app_url
    Capybara.reset_sessions!
  end

  def teardown
    cleanup_test_data if @visitor_id
    Capybara.reset_sessions!
  end

  private

  def sdk_app_url
    case ENV.fetch("SDK", "ruby")
    when "ruby" then "http://localhost:4001"
    when "node" then "http://localhost:4002"
    else raise "Unknown SDK: #{ENV['SDK']}"
    end
  end

  def verify_test_data(visitor_id: nil, user_id: nil)
    # Query verification endpoint
    VerificationHelper.verify(visitor_id: visitor_id, user_id: user_id)
  end

  def cleanup_test_data
    VerificationHelper.cleanup(visitor_id: @visitor_id)
  end
end
```

---

## Test Apps

### mbuzz_ruby_testapp (Sinatra, port 4001)

**Location:** `sdk_integration_tests/apps/mbuzz_ruby_testapp/`

**Gemfile:**
```ruby
gem "sinatra", "~> 3.0"
gem "puma", "~> 6.0"
gem "mbuzz", path: "../../../../../mbuzz-ruby"
```

**config.ru:**
```ruby
require_relative "app"
use Mbuzz::Middleware::Tracking
run MbuzzRubyTestapp
```

**Endpoints:**
- `GET /` - HTML page with forms
- `POST /api/event` - Trigger Mbuzz.event()
- `POST /api/identify` - Trigger Mbuzz.identify()
- `POST /api/conversion` - Trigger Mbuzz.conversion()
- `GET /api/ids` - Return current visitor_id, session_id

### mbuzz_node_testapp (Express, port 4002)

**Location:** `sdk_integration_tests/apps/mbuzz_node_testapp/`

**package.json:**
```json
{
  "dependencies": {
    "express": "^4.18.0",
    "cookie-parser": "^1.4.6",
    "mbuzz": "file:../../../../../mbuzz-node"
  }
}
```

### UI (same for both)
- Shows current visitor_id, session_id
- Event form: type + properties JSON
- Identify form: user_id + traits JSON
- Conversion form: type + revenue + properties
- Status display for results

---

## Verification Endpoint (New in Multibuzz)

**File:** `app/controllers/api/v1/test_verification_controller.rb`

**Routes:**
```ruby
namespace :test do
  resource :verification, only: [:show, :destroy]
end
```

**Endpoints:**
- `GET /api/v1/test/verification?visitor_id=...&user_id=...`
  - Returns: visitor, sessions, events, identity, conversions
  - **Only works with test API keys (sk_test_*)**

- `DELETE /api/v1/test/verification?visitor_id=...`
  - Cleans up test data after each test

---

## Test Scenarios (Ruby/Capybara)

**Example:** `sdk_integration_tests/scenarios/first_visit_test.rb`

```ruby
require_relative "../test_helper"

class FirstVisitTest < SdkIntegrationTest
  def test_creates_visitor_and_session_on_first_visit
    visit "/"

    @visitor_id = find("#visitor-id").text
    session_id = find("#session-id").text

    assert_equal 64, @visitor_id.length, "Visitor ID should be 64 chars"
    assert_equal 64, session_id.length, "Session ID should be 64 chars"

    # Wait for async session creation
    sleep 2

    # Verify data in server
    data = verify_test_data(visitor_id: @visitor_id)

    assert_not_nil data[:visitor]
    assert_equal @visitor_id, data[:visitor][:visitor_id]
    assert_equal 1, data[:sessions].length
    assert_equal session_id, data[:sessions].first[:session_id]
  end
end
```

| Test | What it verifies |
|------|------------------|
| **first_visit** | New visitor creates cookies, session created in DB |
| **returning_visit** | Same visitor cookie persists, new session on timeout |
| **event_tracking** | Event stored with properties, URL auto-enriched |
| **identify** | Visitor linked to Identity, traits stored |
| **conversion** | Conversion created, attribution calculated |
| **utm_capture** | UTM params captured in session.initial_utm |
| **concurrent** | Multiple browser sessions have unique IDs |

---

## Running Tests

**File:** `sdk_integration_tests/Rakefile`

```ruby
require "rake/testtask"

namespace :sdk do
  desc "Run all SDK integration tests for all SDKs"
  task :test do
    %w[ruby node].each do |sdk|
      puts "\n=== Testing #{sdk.upcase} SDK ==="
      ENV["SDK"] = sdk
      Rake::Task["sdk:test:scenarios"].execute
    end
  end

  desc "Run SDK integration tests for Ruby SDK only"
  task :ruby do
    ENV["SDK"] = "ruby"
    Rake::Task["sdk:test:scenarios"].execute
  end

  desc "Run SDK integration tests for Node SDK only"
  task :node do
    ENV["SDK"] = "node"
    Rake::Task["sdk:test:scenarios"].execute
  end

  namespace :test do
    Rake::TestTask.new(:scenarios) do |t|
      t.libs << "."
      t.test_files = FileList["scenarios/*_test.rb"]
      t.verbose = true
    end
  end

  desc "Start Ruby test app"
  task :app_ruby do
    sh "cd apps/mbuzz_ruby_testapp && bundle exec rackup -p 4001"
  end

  desc "Start Node test app"
  task :app_node do
    sh "cd apps/mbuzz_node_testapp && npx tsx server.ts"
  end
end
```

**Commands:**

```bash
# Prerequisites
export MBUZZ_API_KEY=sk_test_your_key
export MBUZZ_API_URL=http://localhost:3000/api/v1

# One-time setup
cd sdk_integration_tests
bundle install
cd apps/mbuzz_ruby_testapp && bundle install
cd ../mbuzz_node_testapp && npm install
npx playwright install chromium  # Install browser

# Start test apps (in separate terminals)
rake sdk:app_ruby  # http://localhost:4001
rake sdk:app_node  # http://localhost:4002

# Run ALL SDK tests (both Ruby and Node)
rake sdk:test

# Run ONLY Ruby SDK tests
rake sdk:ruby

# Run ONLY Node SDK tests
rake sdk:node
```

**Isolation from Rails minitest:**
- Lives in separate directory with own Gemfile
- Test files don't match Rails pattern (`test/**/test_*.rb` or `test/**/*_test.rb` in Rails test dir)
- `rails test` won't pick these up

---

## Implementation Sequence

### Phase 1: Multibuzz Changes
- [ ] Create `TestVerificationController`
- [ ] Add routes for `/api/v1/test/verification`
- [ ] Test endpoint with curl

### Phase 2: Test Infrastructure
- [ ] Create `sdk_integration_tests/` directory
- [ ] Create Gemfile with capybara-playwright-driver
- [ ] Create test_helper.rb with Capybara/Playwright setup
- [ ] Create verification_helper.rb
- [ ] Create Rakefile with test tasks

### Phase 3: Ruby Test App (mbuzz_ruby_testapp)
- [ ] Create Sinatra app with Mbuzz middleware
- [ ] Create HTML UI with forms
- [ ] Test manually in browser

### Phase 4: Node Test App (mbuzz_node_testapp)
- [ ] Create Express app with Mbuzz middleware
- [ ] Create HTML UI with forms
- [ ] Test manually in browser

### Phase 5: Test Scenarios
- [ ] first_visit_test.rb
- [ ] event_tracking_test.rb
- [ ] identify_test.rb
- [ ] conversion_test.rb
- [ ] utm_capture_test.rb
- [ ] returning_visit_test.rb
- [ ] concurrent_test.rb

### Phase 6: Documentation
- [ ] `sdk_integration_tests/README.md` with setup instructions
- [ ] Troubleshooting guide

### Phase 7: Update Global README
- [ ] Add section to main `README.md` about SDK integration testing
- [ ] Brief description and link to `sdk_integration_tests/README.md`

---

## Global README Update

Add to `/Users/vlad/code/multibuzz/README.md`:

```markdown
## SDK Integration Testing

End-to-end tests for mbuzz SDKs live in `sdk_integration_tests/`. These tests:
- Run minimal test apps with each SDK (Ruby, Node.js)
- Use Capybara + Playwright for browser automation
- Verify data is correctly stored in the server

**Quick start:**
```bash
cd sdk_integration_tests
bundle install
# See sdk_integration_tests/README.md for full setup
```

**Run tests:**
```bash
rake sdk:test      # All SDKs
rake sdk:ruby      # Ruby SDK only
rake sdk:node      # Node SDK only
```

See [sdk_integration_tests/README.md](sdk_integration_tests/README.md) for detailed setup and troubleshooting.
```

---

## Critical Files

**Multibuzz (to create/modify):**
- `app/controllers/api/v1/test_verification_controller.rb` (new)
- `config/routes.rb` (add test namespace)

**Test infrastructure (to create):**
- `sdk_integration_tests/Gemfile`
- `sdk_integration_tests/test_helper.rb`
- `sdk_integration_tests/Rakefile`
- `sdk_integration_tests/helpers/verification_helper.rb`
- `sdk_integration_tests/helpers/test_config.rb`

**Test apps (to create):**
- `sdk_integration_tests/apps/mbuzz_ruby_testapp/app.rb`
- `sdk_integration_tests/apps/mbuzz_ruby_testapp/Gemfile`
- `sdk_integration_tests/apps/mbuzz_ruby_testapp/config.ru`
- `sdk_integration_tests/apps/mbuzz_node_testapp/server.ts`
- `sdk_integration_tests/apps/mbuzz_node_testapp/package.json`

**Test scenarios (to create):**
- `sdk_integration_tests/scenarios/first_visit_test.rb`
- `sdk_integration_tests/scenarios/event_tracking_test.rb`
- `sdk_integration_tests/scenarios/identify_test.rb`
- `sdk_integration_tests/scenarios/conversion_test.rb`
- `sdk_integration_tests/scenarios/utm_capture_test.rb`
- `sdk_integration_tests/scenarios/returning_visit_test.rb`
- `sdk_integration_tests/scenarios/concurrent_test.rb`

**SDKs (reference only):**
- `../mbuzz-ruby/lib/mbuzz/middleware/tracking.rb`
- `../mbuzz-node/src/middleware/express.ts`
