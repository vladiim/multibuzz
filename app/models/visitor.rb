# frozen_string_literal: true

class Visitor < ApplicationRecord
  include Visitor::Validations
  include Visitor::Relationships
  include Visitor::Scopes
  include Visitor::Tracking
  include Visitor::Callbacks

  has_prefix_id :vis

  # Strips leading/trailing double-quote characters introduced by client SDKs that
  # JSON.stringify the cookie value on every write without JSON.parse on read,
  # accumulating one quote pair per session call. Embedded quotes are preserved.
  def self.normalize_id(value)
    return value if value.nil?

    value.to_s.gsub(/\A"+|"+\z/, "")
  end
end
