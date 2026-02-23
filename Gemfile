# frozen_string_literal: true

source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# TimescaleDB for time-series optimization [https://github.com/jonatas/timescaledb]
gem "timescaledb", "~> 0.2.0"
# OpenStruct is required by timescaledb gem but not included in Ruby 3.x by default
gem "ostruct"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails", "~> 3.0"
gem "tailwindcss-ruby", "~> 3.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# CORS support for API endpoints [https://github.com/cyu/rack-cors]
gem "rack-cors"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Stripe for payment processing [https://github.com/stripe/stripe-ruby]
gem "stripe"

# Postmark for transactional emails [https://github.com/ActiveCampaign/postmark-rails]
gem "postmark-rails"

# Mbuzz SDK for dogfooding [https://rubygems.org/gems/mbuzz]
gem "mbuzz", "~> 0.7.5"

# Use prefixed IDs for customer-facing identifiers [https://github.com/excid3/prefixed_ids]
gem "prefixed_ids"

# Markdown rendering for documentation [https://github.com/vmg/redcarpet]
gem "redcarpet"
gem "rouge"

# Frontmatter parsing for articles [https://github.com/waiting-for-dev/front_matter_parser]
gem "front_matter_parser"

# Ruby AST parser for AML DSL validation [https://github.com/whitequark/parser]
gem "parser"

# CSV processing (no longer default gem in Ruby 3.4+)
gem "csv"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "solid_errors"

# S3-compatible storage for log archival to DigitalOcean Spaces
gem "aws-sdk-s3"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # --- Static analysis tools ---

  # Gem dependency vulnerability scanning [https://github.com/rubysec/bundler-audit]
  gem "bundler-audit", require: false

  # RuboCop extensions
  gem "rubocop-minitest", require: false
  gem "rubocop-thread_safety", require: false

  # ERB template linting [https://github.com/Shopify/erb_lint]
  gem "erb_lint", require: false

  # Code smell detection [https://github.com/troessner/reek]
  gem "reek", require: false

  # N+1 query detection [https://github.com/charkost/prosopite]
  gem "prosopite"
  gem "pg_query"

  # Unsafe migration prevention [https://github.com/ankane/strong_migrations]
  gem "strong_migrations"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Database schema/validation consistency [https://github.com/djezzzl/database_consistency]
  gem "database_consistency", require: false

  # Missing index detection [https://github.com/gregnavis/active_record_doctor]
  gem "active_record_doctor"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # Test coverage [https://github.com/simplecov-ruby/simplecov]
  gem "simplecov", require: false

  # Diff-based coverage enforcement [https://github.com/grodowski/undercover]
  gem "undercover", require: false

  # Performance testing [https://github.com/evanphx/benchmark-ips]
  gem "benchmark-ips"

  # Memory allocation profiling [https://github.com/SamSaffron/memory_profiler]
  gem "memory_profiler"
end
