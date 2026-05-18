# frozen_string_literal: true

module ReattributionBatch::Enums
  extend ActiveSupport::Concern

  included do
    enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
    enum :trigger, { identity_merge: 0, billing_unlock: 1 }
  end
end
