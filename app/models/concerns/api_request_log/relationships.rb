# frozen_string_literal: true

module ApiRequestLog::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account, optional: true
  end
end
