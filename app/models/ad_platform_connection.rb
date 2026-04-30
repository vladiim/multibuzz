# frozen_string_literal: true

class AdPlatformConnection < ApplicationRecord
  include AdPlatformConnection::Validations
  include AdPlatformConnection::Relationships
  include AdPlatformConnection::StatusManagement
  include AdPlatformConnection::AdSpend

  has_prefix_id :adcon

  encrypts :access_token
  encrypts :refresh_token

  enum :platform, { google_ads: 0, meta_ads: 1, linkedin_ads: 2, tiktok_ads: 3 }
  enum :status, { connected: 0, syncing: 1, error: 2, disconnected: 3, needs_reauth: 4 }

  # Returns the connection's single metadata pair as `[key, value]`, or nil when
  # absent or multi-valued. Today the editor + MetadataLinkCheck both assume a
  # single pair (multi-key UI is a follow-up); this method is the single source
  # of that assumption so views and services stay aligned.
  def metadata_pair
    return nil unless metadata.is_a?(Hash) && metadata.size == 1

    metadata.first
  end
end
