# frozen_string_literal: true

module AccountCredit::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :applied_plan, class_name: "Plan"
  end
end
