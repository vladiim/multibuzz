module Event::Scopes
  extend ActiveSupport::Concern

  included do
    default_scope { production }

    scope :production, -> { where(is_test: false) }
    scope :test_data, -> { where(is_test: true) }
    scope :by_type, ->(type) { where(event_type: type) }
    scope :recent, -> { order(occurred_at: :desc) }
    scope :between, ->(start_time, end_time) { where(occurred_at: start_time..end_time) }
    scope :with_utm_source, ->(source) { where("properties->>'utm_source' = ?", source) }
    scope :with_utm_medium, ->(medium) { where("properties->>'utm_medium' = ?", medium) }
    scope :with_utm_campaign, ->(campaign) { where("properties->>'utm_campaign' = ?", campaign) }
  end
end
