# frozen_string_literal: true

module AccountCredit::Enums
  extend ActiveSupport::Concern

  included do
    enum :status, { active: 0, voided: 1 }
  end
end
