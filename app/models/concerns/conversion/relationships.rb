# frozen_string_literal: true

module Conversion::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :visitor
    # No foreign key due to TimescaleDB composite PK
    # belongs_to :session
    # belongs_to :event

    has_many :attribution_credits, dependent: :destroy
  end
end
