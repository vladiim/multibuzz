module Session::Callbacks
  extend ActiveSupport::Concern

  included do
    before_create :set_started_at
  end

  private

  def set_started_at
    self.started_at ||= Time.current
  end
end
