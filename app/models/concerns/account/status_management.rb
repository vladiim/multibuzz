module Account::StatusManagement
  extend ActiveSupport::Concern

  def suspend!
    update!(status: :suspended, suspended_at: Time.current)
  end

  def cancel!
    update!(status: :cancelled, cancelled_at: Time.current)
  end

  def reactivate!
    update!(status: :active, suspended_at: nil, cancelled_at: nil)
  end
end
