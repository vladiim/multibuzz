# frozen_string_literal: true

class AdSpendSyncRun < ApplicationRecord
  include AdSpendSyncRun::Validations
  include AdSpendSyncRun::Relationships

  enum :status, { pending: 0, running: 1, completed: 2, failed: 3 }
end
