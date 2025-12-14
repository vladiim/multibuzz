# frozen_string_literal: true

module RerunJob::Validations
  extend ActiveSupport::Concern

  included do
    validates :total_conversions, presence: true, numericality: { greater_than: 0 }
    validates :from_version, presence: true
    validates :to_version, presence: true
  end
end
