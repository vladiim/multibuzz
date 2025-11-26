# Local Development Setup

Complete guide to setting up mbuzz for local development.

---

## Prerequisites

### Required

- **Ruby 3.4.3**
- **PostgreSQL 18+**
- **TimescaleDB 2.23.1+**
- **Node.js 18+** (for Tailwind CSS compilation)
- **Git**

### Optional

- **Homebrew** (macOS package manager)
- **Docker** (alternative to local PostgreSQL)

---

## macOS Setup

### 1. Install Ruby

Using rbenv (recommended):

```bash
# Install rbenv
brew install rbenv ruby-build

# Install Ruby 3.4.3
rbenv install 3.4.3
rbenv global 3.4.3

# Verify
ruby -v  # Should show ruby 3.4.3
```

### 2. Install PostgreSQL + TimescaleDB

```bash
# Install PostgreSQL 18
brew install postgresql@18
brew services start postgresql@18

# Install TimescaleDB
brew tap timescale/tap
brew install timescaledb

# Move TimescaleDB files to PostgreSQL
timescaledb_move.sh

# Configure PostgreSQL for TimescaleDB
timescaledb-tune --quiet --yes

# Restart PostgreSQL
brew services restart postgresql@18
```

### 3. Install Node.js

```bash
# Install Node.js
brew install node

# Verify
node -v  # Should show v18 or higher
```

---

## Clone & Install

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/multibuzz.git
cd multibuzz
```

### 2. Install Dependencies

```bash
# Install Ruby gems
bundle install

# Install Node packages (for Tailwind)
npm install
```

---

## Database Setup

### 1. Create Database

```bash
bin/rails db:create
```

This creates:
- `multibuzz_development`
- `multibuzz_test`

### 2. Run Migrations

```bash
bin/rails db:migrate
```

### 3. Verify TimescaleDB

```bash
bin/rails runner "puts ActiveRecord::Base.connection.execute('SELECT extname FROM pg_extension WHERE extname = \'timescaledb\'').first"
```

Should output: `{"extname"=>"timescaledb"}`

### 4. Seed Data (Optional)

```bash
bin/rails db:seed
```

Creates:
- Sample account
- Test API keys
- Sample events

---

## Configuration

### 1. Environment Variables

Create `.env` file in project root:

```bash
# Copy example
cp .env.example .env
```

Edit `.env`:

```bash
# Database
DATABASE_URL=postgresql://localhost/multibuzz_development

# Rails
RAILS_ENV=development
SECRET_KEY_BASE=your_secret_key_here

# Optional: mbuzz API key for testing gem
MBUZZ_API_KEY=sk_test_your_key_here
```

### 2. Generate Secret Key

```bash
bin/rails secret
```

Copy output to `SECRET_KEY_BASE` in `.env`

---

## Running the Application

### 1. Start the Server

```bash
bin/dev
```

This starts:
- **Rails server** on http://localhost:3000
- **Tailwind CSS** watch mode (auto-recompile on changes)

**Alternative (Rails only)**:

```bash
bin/rails server
```

### 2. Compile Assets Manually

If you need to compile Tailwind CSS separately:

```bash
bin/rails tailwindcss:build
```

Or watch for changes:

```bash
bin/rails tailwindcss:watch
```

---

## Verify Setup

### 1. Open Browser

Visit: http://localhost:3000

You should see the mbuzz homepage.

### 2. Check Health Endpoint

```bash
curl http://localhost:3000/api/v1/health
```

Should return: `{"status":"ok"}`

### 3. Run Tests

```bash
bin/rails test
```

Should show:
```
242 tests, 1621 assertions, 0 failures, 0 errors, 0 skips
```

---

## Development Workflow

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Changes

- Edit code
- Tailwind auto-recompiles (if using `bin/dev`)
- Turbo auto-refreshes browser

### 3. Run Tests

```bash
# All tests
bin/rails test

# Specific file
bin/rails test test/models/account_test.rb

# Specific test
bin/rails test test/models/account_test.rb:12
```

### 4. Check Code Style

```bash
# Run RuboCop
bin/rubocop

# Auto-fix issues
bin/rubocop -a
```

### 5. Commit Changes

```bash
git add .
git commit -m "feat(events): add batch event processing"
```

See [CLAUDE.md](../../CLAUDE.md) for commit conventions.

---

## Common Tasks

### Reset Database

```bash
bin/rails db:drop db:create db:migrate db:seed
```

### Open Rails Console

```bash
bin/rails console
```

### Open Database Console

```bash
bin/rails dbconsole
```

### Generate New Model

```bash
bin/rails generate model ModelName field:type
```

### Generate New Service

```bash
# Create file manually in app/services/namespace/
# Follow pattern: app/services/events/action_service.rb
```

### View Routes

```bash
bin/rails routes
```

Or specific routes:

```bash
bin/rails routes | grep events
```

---

## Troubleshooting

### PostgreSQL Not Running

```bash
# Check status
brew services list | grep postgresql

# Start
brew services start postgresql@18

# Restart
brew services restart postgresql@18
```

### TimescaleDB Extension Missing

```bash
# Reinstall TimescaleDB
brew reinstall timescaledb

# Move files
timescaledb_move.sh

# Restart PostgreSQL
brew services restart postgresql@18

# Recreate database
bin/rails db:drop db:create db:migrate
```

### Gem Installation Fails

```bash
# Update bundler
gem install bundler

# Clean and reinstall
bundle clean --force
bundle install
```

### Tailwind Not Compiling

```bash
# Rebuild Tailwind
bin/rails tailwindcss:build

# Or force reinstall
npm install
bin/rails tailwindcss:build
```

### Port 3000 Already in Use

```bash
# Find process
lsof -i :3000

# Kill process
kill -9 <PID>

# Or use different port
bin/rails server -p 3001
```

---

## IDE Setup

### VS Code (Recommended)

Install extensions:
- **Ruby** by Peng Lv
- **Tailwind CSS IntelliSense** by Tailwind Labs
- **ERB Formatter/Beautify** by Ali Atatu
- **Stimulus LSP** by Marco Roth

Settings (`.vscode/settings.json`):

```json
{
  "editor.formatOnSave": true,
  "ruby.format": "rubocop",
  "tailwindCSS.experimental.classRegex": [
    ["class:\\s*['\"]([^'\"]*)['\"]"]
  ]
}
```

### RubyMine

- Built-in Ruby support
- Enable Tailwind CSS plugin
- Set RuboCop as code formatter

---

## Testing Tools

### Run Specific Test Types

```bash
# Model tests
bin/rails test:models

# Service tests
bin/rails test:services

# Controller tests
bin/rails test:controllers

# Integration tests
bin/rails test:integration

# System tests (browser)
bin/rails test:system
```

### Test Coverage

```bash
# Install SimpleCov (if not already)
gem install simplecov

# Run tests with coverage
COVERAGE=true bin/rails test
```

---

## Working with the API

### Create Test API Key

```bash
bin/rails console

# In console:
account = Account.first
api_key = ApiKeys::GenerationService.new(account, environment: :test).call
puts "API Key: #{api_key[:plain_key]}"
```

### Test API with cURL

```bash
# Store API key
export MBUZZ_API_KEY=sk_test_your_key_here

# Test event ingestion
curl -X POST http://localhost:3000/api/v1/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "123",
    "event": "Test Event",
    "properties": {
      "test": true
    }
  }'
```

---

## Next Steps

1. Read [CLAUDE.md](../../CLAUDE.md) for coding standards
2. Check `lib/specs/` for feature specifications
3. Review `app/services/` to understand the service object pattern
4. Look at tests in `test/` for examples
5. Start contributing!

---

## Resources

- **Rails Guides**: https://guides.rubyonrails.org
- **TimescaleDB Docs**: https://docs.timescale.com
- **Tailwind CSS**: https://tailwindcss.com/docs
- **Stimulus**: https://stimulus.hotwired.dev
- **Turbo**: https://turbo.hotwired.dev

---

**Questions?** Check the docs in `lib/docs/architecture/` or ask in GitHub Issues.
