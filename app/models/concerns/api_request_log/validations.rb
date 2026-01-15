# frozen_string_literal: true

module ApiRequestLog::Validations
  extend ActiveSupport::Concern

  included do
    validates :request_id, presence: true
    validates :endpoint, presence: true
    validates :http_method, presence: true
    validates :http_status, presence: true
    validates :error_type, presence: true
    validates :occurred_at, presence: true
  end
end
