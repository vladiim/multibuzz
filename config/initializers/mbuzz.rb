# frozen_string_literal: true

# Dogfooding: Track our own usage with Mbuzz
Mbuzz.init(
  api_key: Rails.application.credentials.dig(:mbuzz, :api_token),
  debug: Rails.env.development?
)
