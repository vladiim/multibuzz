# frozen_string_literal: true

module Visitor::Validations
  extend ActiveSupport::Concern

  ID_FORMAT = /\A[a-zA-Z0-9._:\-]{1,}\z/
  ID_FORMAT_MESSAGE = "must contain only letters, numbers, underscores, hyphens, dots, and colons"

  included do
    validates :visitor_id,
      presence: true,
      uniqueness: { scope: :account_id },
      length: { maximum: 255 },
      format: { with: ID_FORMAT, message: ID_FORMAT_MESSAGE }
  end
end
