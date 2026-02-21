# frozen_string_literal: true

# CORS configuration for API endpoints
# Allows requests from any origin since SDKs run on customer domains

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"

    resource "/api/*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      expose: [ "X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset" ],
      max_age: 86400
  end
end
