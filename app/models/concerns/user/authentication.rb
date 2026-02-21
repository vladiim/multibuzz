# frozen_string_literal: true

module User::Authentication
  extend ActiveSupport::Concern

  included do
    has_secure_password
  end
end
