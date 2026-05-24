# frozen_string_literal: true

module AccountCredit::Validations
  extend ActiveSupport::Concern

  included do
    validates :amount_cents, presence: true, numericality: { greater_than: 0 }
    validates :source, presence: true
    validates :granted_at, presence: true
  end
end
