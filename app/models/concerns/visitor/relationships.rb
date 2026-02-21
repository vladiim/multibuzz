# frozen_string_literal: true

module Visitor::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :identity, optional: true, inverse_of: :visitors, class_name: "Identity"
    has_many :sessions, dependent: :destroy
    has_many :events, dependent: :destroy
  end
end
