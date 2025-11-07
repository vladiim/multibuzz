module Visitor::Tracking
  extend ActiveSupport::Concern

  def touch_last_seen!
    update_column(:last_seen_at, Time.current)
  end
end
