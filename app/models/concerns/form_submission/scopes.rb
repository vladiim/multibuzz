module FormSubmission::Scopes
  extend ActiveSupport::Concern

  included do
    scope :recent, -> { order(created_at: :desc) }
    scope :by_type, ->(type) { where(type: type) }
  end
end
