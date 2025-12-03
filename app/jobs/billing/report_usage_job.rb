# frozen_string_literal: true

module Billing
  class ReportUsageJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      ReportUsageService.new(Account.find(account_id)).call
    end
  end
end
