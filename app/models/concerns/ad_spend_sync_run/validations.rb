# frozen_string_literal: true

module AdSpendSyncRun::Validations
  extend ActiveSupport::Concern

  included do
    validates :sync_date, presence: true
    validates :status, presence: true
  end
end
