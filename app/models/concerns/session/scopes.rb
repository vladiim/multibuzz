module Session::Scopes
  extend ActiveSupport::Concern

  included do
    default_scope { production }

    scope :production, -> { where(is_test: false) }
    scope :test_data, -> { where(is_test: true) }
    scope :active, -> { where(ended_at: nil) }
    scope :ended, -> { where.not(ended_at: nil) }
    scope :recent, -> { where("started_at >= ?", 30.days.ago).order(started_at: :desc) }
  end
end
