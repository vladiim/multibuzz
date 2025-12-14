# frozen_string_literal: true

module Conversions
  class PropertyKeyDiscoveryJob < ApplicationJob
    queue_as :low

    def perform(account_id = nil)
      account_id ? process_single(account_id) : process_all
    end

    private

    def process_single(account_id)
      PropertyKeyDiscoveryService.new(Account.find(account_id)).call
    end

    def process_all
      Account.active.find_each { |account| PropertyKeyDiscoveryService.new(account).call }
    end
  end
end
