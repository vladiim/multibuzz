class BillingEvent < ApplicationRecord
  belongs_to :account, optional: true

  validates :stripe_event_id, presence: true, uniqueness: true
  validates :event_type, presence: true

  scope :processed, -> { where.not(processed_at: nil) }
  scope :pending, -> { where(processed_at: nil) }

  def processed?
    processed_at.present?
  end

  def mark_processed!
    update!(processed_at: Time.current)
  end

  def self.already_processed?(stripe_event_id)
    exists?(stripe_event_id: stripe_event_id)
  end
end
