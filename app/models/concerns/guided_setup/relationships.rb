# frozen_string_literal: true

module GuidedSetup::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
  end
end
