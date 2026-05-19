# frozen_string_literal: true

module GuidedSetup::Validations
  extend ActiveSupport::Concern

  included do
    validates :account_id, uniqueness: true
  end
end
