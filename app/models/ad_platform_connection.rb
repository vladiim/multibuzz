# frozen_string_literal: true

class AdPlatformConnection < ApplicationRecord
  include AdPlatformConnection::Validations
  include AdPlatformConnection::Relationships
  include AdPlatformConnection::StatusManagement

  has_prefix_id :adcon

  encrypts :access_token
  encrypts :refresh_token

  enum :platform, { google_ads: 0, meta_ads: 1, linkedin_ads: 2, tiktok_ads: 3 }
  enum :status, { connected: 0, syncing: 1, error: 2, disconnected: 3 }
end
