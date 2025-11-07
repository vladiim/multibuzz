module Session::Tracking
  extend ActiveSupport::Concern

  def active?
    ended_at.nil?
  end

  def ended?
    ended_at.present?
  end

  def increment_page_views!
    increment!(:page_view_count)
  end

  def end_session!
    update!(ended_at: Time.current)
  end
end
