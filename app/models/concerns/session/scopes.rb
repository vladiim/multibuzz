module Session::Scopes
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(ended_at: nil) }
    scope :ended, -> { where.not(ended_at: nil) }
    scope :recent, -> { where("started_at >= ?", 30.days.ago).order(started_at: :desc) }
  end
end
