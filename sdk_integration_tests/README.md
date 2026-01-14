# SDK Integration Tests

End-to-end integration tests for mbuzz SDKs using Capybara + Playwright.

## Overview

This test suite:
- **Automatically creates** a test account and API key at the start of each test run
- Runs minimal test apps for each SDK (Ruby, Node.js)
- Verifies visitor/session cookies, events, identification, and conversions
- **Automatically tears down** the test account after tests complete

## Prerequisites

- Ruby 3.x
- Node.js 18+
- **Main multibuzz app must be running** (`bin/dev` or `rails server`)

**IMPORTANT**: The SDK integration tests require the main Multibuzz Rails app to be running on `localhost:3000`. Without it, tests will fail with "Connection refused" or "404 Not Found" errors. The main app provides:
- Test account setup endpoint (`POST /api/v1/test/setup`)
- Test data verification endpoint (`GET /api/v1/test/verification`)
- Event/conversion API endpoints

Start the main app first:
```bash
cd /path/to/multibuzz
bin/dev
```

## Directory Structure

```
sdk_integration_tests/
├── Gemfile                    # Test framework dependencies
├── Rakefile                   # Test runner tasks
├── test_helper.rb             # Base test class
├── helpers/
│   ├── test_config.rb         # Environment configuration
│   ├── test_setup_helper.rb   # Account/key setup & teardown
│   └── verification_helper.rb # API verification client
├── scenarios/                 # Test scenarios
│   ├── first_visit_test.rb
│   ├── event_tracking_test.rb
│   ├── identify_test.rb
│   ├── conversion_test.rb
│   ├── utm_capture_test.rb
│   ├── returning_visit_test.rb
│   └── concurrent_test.rb
└── apps/
    ├── mbuzz_ruby_testapp/    # Sinatra test app (port 4001)
    └── mbuzz_node_testapp/    # Express test app (port 4002)
```

**Note**: This directory lives at the project root (not inside `test/`) to ensure complete isolation from the Rails test runner.

## Quick Start

### 1. Install Dependencies

```bash
cd sdk_integration_tests
bundle install

# Ruby test app
cd apps/mbuzz_ruby_testapp && bundle install && cd ../..

# Node test app
cd apps/mbuzz_node_testapp && npm install && cd ../..

# Playwright browser
npx playwright install chromium
```

### 2. Start Main Multibuzz App

**This step is required.** In a separate terminal:
```bash
cd /path/to/multibuzz
bin/dev  # or: rails server
```

Wait until you see "Listening on http://localhost:3000" before proceeding.

### 3. Start Test Apps

In separate terminals:

```bash
# First, create a test account
cd sdk_integration_tests
rake sdk:setup:create
# Note the API key output

# Terminal 1 - Ruby test app
export MBUZZ_API_KEY=sk_test_xxx  # From above
export MBUZZ_API_URL=http://localhost:3000/api/v1
rake sdk:app_ruby

# Terminal 2 - Node test app
export MBUZZ_API_KEY=sk_test_xxx
export MBUZZ_API_URL=http://localhost:3000/api/v1
rake sdk:app_node
```

### 4. Run Tests

```bash
cd sdk_integration_tests

# Run ALL SDK tests (Ruby and Node)
# Automatically creates/tears down test account
rake sdk:test

# Run Ruby SDK tests only
rake sdk:ruby

# Run Node SDK tests only
rake sdk:node

# Run with visible browser (debugging)
HEADLESS=false rake sdk:ruby
```

## How It Works

1. **Setup**: `rake sdk:test` creates a test account via `POST /api/v1/test/setup`
2. **Run**: Tests run against the test apps, verifying data via `/api/v1/test/verification`
3. **Teardown**: Test account is deleted via `DELETE /api/v1/test/setup`

The test account slug starts with `sdk-test-` and is automatically cleaned up.

## Test Scenarios

| Test File | What It Tests |
|-----------|--------------|
| `first_visit_test.rb` | Visitor/session creation, cookie persistence |
| `event_tracking_test.rb` | Event tracking via SDK, URL enrichment |
| `identify_test.rb` | User identification, trait updates |
| `conversion_test.rb` | Conversion tracking, revenue, acquisition |
| `utm_capture_test.rb` | UTM parameter capture, referrer tracking |
| `returning_visit_test.rb` | Visitor persistence, session management |
| `concurrent_test.rb` | Multiple sessions, rapid events |
| `background_job_visitor_test.rb` | Background job context, explicit visitor_id |

## Test Apps

### Ruby Test App (Sinatra)

- **Port**: 4001
- **URL**: http://localhost:4001
- **SDK**: `mbuzz` gem (local path to mbuzz-ruby)

### Node Test App (Express)

- **Port**: 4002
- **URL**: http://localhost:4002
- **SDK**: `mbuzz` npm package (local path to mbuzz-node)

### Test App UI

Both apps provide:
- Current visitor/session/user IDs display
- Event tracking form
- Identify form
- Conversion tracking form

## Rake Tasks

| Task | Description |
|------|-------------|
| `rake sdk:test` | Run all SDK tests (creates/tears down account) |
| `rake sdk:ruby` | Run Ruby SDK tests only |
| `rake sdk:node` | Run Node SDK tests only |
| `rake sdk:app_ruby` | Start Ruby test app (port 4001) |
| `rake sdk:app_node` | Start Node test app (port 4002) |
| `rake sdk:setup:create` | Create test account (for manual testing) |
| `rake sdk:setup:destroy` | Tear down test account |
| `rake sdk:setup:all` | Install all dependencies |

## Troubleshooting

### "Connection refused" errors

Ensure all servers are running:
1. Main multibuzz app (`rails server`)
2. Test app for the SDK being tested

### Browser not launching

```bash
npx playwright install chromium
```

### Tests timing out

- Increase `wait_for_async` delays in test files
- Verify main app is processing requests
- Check Rails server logs for errors

### Manual cleanup

If tests fail and leave data behind:
```bash
rake sdk:setup:destroy
```

## Adding New SDKs

1. Create test app in `apps/mbuzz_{sdk}_testapp/`
2. Add port mapping in `helpers/test_config.rb`
3. Add rake task in `Rakefile`
4. Test scenarios run automatically via `SDK=sdk_name`

## Notes

- Tests automatically create test API keys (`sk_test_*`)
- Setup/verification endpoints only work in development/test environments
- Test accounts are prefixed with `sdk-test-` and auto-deleted
- Failing tests still trigger teardown (via `ensure` block)
