# frozen_string_literal: true

module AdSpendRecord::Validations
  extend ActiveSupport::Concern

  included do
    validates :spend_date, presence: true
    validates :channel, presence: true, inclusion: { in: Channels::ALL }
    validates :platform_campaign_id, presence: true
    validates :campaign_name, presence: true
    validates :currency, presence: true, length: { maximum: 3 }
    validates :spend_micros, numericality: { greater_than_or_equal_to: 0 }
    validates :impressions, numericality: { greater_than_or_equal_to: 0 }
    validates :clicks, numericality: { greater_than_or_equal_to: 0 }
  end
end
