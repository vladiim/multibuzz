# frozen_string_literal: true

module User::Roles
  extend ActiveSupport::Concern

  def admin?
    is_admin?
  end
end
