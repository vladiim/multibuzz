# frozen_string_literal: true

# One row per (conversion × destination) dispatch attempt. Records what
# happened: payload sent, platform response, error, retries, the
# attribution model + credit share that decided the dispatch.
#
# Statuses are an enum-as-string so admin filters can use plain strings
# and so future statuses can be added without a migration.
class ConversionDispatch < ApplicationRecord
  module Statuses
    PENDING                  = "pending"
    DELIVERED                = "delivered"
    SKIPPED_NO_IDENTITY      = "skipped_no_identity"
    SKIPPED_NO_CREDIT        = "skipped_no_credit"
    SKIPPED_ACCOUNT_SUSPENDED = "skipped_account_suspended"
    TOKEN_FAILED             = "token_failed"
    FAILED_TRANSIENT         = "failed_transient"
    FAILED_PERMANENT         = "failed_permanent"

    ALL = [
      PENDING, DELIVERED,
      SKIPPED_NO_IDENTITY, SKIPPED_NO_CREDIT, SKIPPED_ACCOUNT_SUSPENDED,
      TOKEN_FAILED, FAILED_TRANSIENT, FAILED_PERMANENT
    ].freeze

    SKIPPED_PREFIX = "skipped_"
    FAILED_PREFIX = "failed_"
  end

  has_prefix_id :cdisp

  belongs_to :conversion
  belongs_to :conversion_destination
  belongs_to :account
  belongs_to :attribution_model, optional: true

  validates :status, presence: true, inclusion: { in: Statuses::ALL }
  validates :conversion_id, uniqueness: { scope: :conversion_destination_id }

  scope :delivered,    -> { where(status: Statuses::DELIVERED) }
  scope :pending,      -> { where(status: Statuses::PENDING) }
  scope :recent_first, -> { order(created_at: :desc) }

  def delivered?
    status == Statuses::DELIVERED
  end

  def pending?
    status == Statuses::PENDING
  end

  def skipped?
    status.to_s.start_with?(Statuses::SKIPPED_PREFIX)
  end

  def failed?
    status.to_s.start_with?(Statuses::FAILED_PREFIX) || status == Statuses::TOKEN_FAILED
  end
end
