# frozen_string_literal: true

require_relative "app"

# Configure Mbuzz BEFORE the tracking middleware runs.
# CredentialLoader reads .test_env on every call, so credentials are always fresh.
# This must be a separate middleware because Sinatra's `before` block runs AFTER
# the tracking middleware — too late for session creation in the background thread.
use(Class.new do
  def initialize(app)
    @app = app
  end

  def call(env)
    Mbuzz.init(
      api_key: CredentialLoader.api_key,
      api_url: CredentialLoader.api_url,
      debug: ENV.fetch("MBUZZ_DEBUG", "false") == "true"
    )
    @app.call(env)
  end
end)

# Mbuzz tracking middleware - handles cookies and session creation
use Mbuzz::Middleware::Tracking

run MbuzzRubyTestapp
