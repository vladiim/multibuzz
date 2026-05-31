# frozen_string_literal: true

module CustomDimensions
  class BackfillJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      BackfillService.new(Account.find(account_id)).call
    end
  end
end
