# frozen_string_literal: true

module Identity::Scopes
  extend ActiveSupport::Concern

  included do
    scope :production, -> { where(is_test: false) }
    scope :test_data, -> { where(is_test: true) }
    scope :recently_identified, -> { order(last_identified_at: :desc) }
  end
end
