# frozen_string_literal: true

module ApiRequestLog::Scopes
  extend ActiveSupport::Concern

  included do
    scope :by_account, ->(account) { where(account: account) }
    scope :by_error_type, ->(type) { where(error_type: type) }
    scope :by_endpoint, ->(endpoint) { where(endpoint: endpoint) }
    scope :recent, ->(duration) { where("occurred_at > ?", duration.ago) }
  end
end
