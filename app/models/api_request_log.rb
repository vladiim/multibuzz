# frozen_string_literal: true

class ApiRequestLog < ApplicationRecord
  include ApiRequestLog::Enums
  include ApiRequestLog::Relationships
  include ApiRequestLog::Validations
  include ApiRequestLog::Scopes
end
