# frozen_string_literal: true

Stripe.api_key = Rails.application.credentials.dig(:stripe, :secret_key)

# Optional: Set API version for consistency
# Stripe.api_version = "2024-12-18"
