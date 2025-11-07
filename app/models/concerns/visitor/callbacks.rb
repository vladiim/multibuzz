module Visitor::Callbacks
  extend ActiveSupport::Concern

  included do
    before_create :set_seen_timestamps
  end

  private

  def set_seen_timestamps
    self.first_seen_at ||= Time.current
    self.last_seen_at ||= Time.current
  end
end
