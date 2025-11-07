module Event::Validations
  extend ActiveSupport::Concern

  included do
    validates :event_type, presence: true
    validates :occurred_at, presence: true
    validates :properties, presence: true

    validate :properties_must_be_hash
  end

  private

  def properties_must_be_hash
    return if properties.is_a?(Hash)

    errors.add(:properties, "must be a hash")
  end
end
