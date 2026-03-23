# frozen_string_literal: true

module AdPlatformConnection::StatusManagement
  extend ActiveSupport::Concern

  included do
    scope :active_connections, -> { where(status: [ :connected, :syncing ]) }
  end

  def token_expired?
    token_expires_at.present? && token_expires_at < Time.current
  end

  def mark_syncing!
    update!(status: :syncing)
  end

  def mark_connected!(synced_at: Time.current)
    update!(status: :connected, last_synced_at: synced_at, last_sync_error: nil)
  end

  def mark_error!(message)
    update!(status: :error, last_sync_error: message)
  end

  def mark_needs_reauth!
    update!(status: :needs_reauth)
  end

  def mark_disconnected!
    update!(status: :disconnected, access_token: nil, refresh_token: nil, token_expires_at: nil)
  end
end
