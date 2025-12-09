module RequireAdmin
  extend ActiveSupport::Concern

  included do
    before_action :require_admin_role
  end

  private

  def require_admin_role
    head :forbidden unless current_user.admin_of?(current_account)
  end
end
