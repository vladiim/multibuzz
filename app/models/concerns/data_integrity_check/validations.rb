module DataIntegrityCheck::Validations
  extend ActiveSupport::Concern

  STATUSES = %w[healthy warning critical].freeze

  included do
    validates :check_name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :value, presence: true
    validates :warning_threshold, presence: true
    validates :critical_threshold, presence: true
  end
end
