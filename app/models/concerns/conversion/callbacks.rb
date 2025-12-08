# frozen_string_literal: true

module Conversion::Callbacks
  extend ActiveSupport::Concern

  included do
    after_create_commit :queue_attribution_calculation
    after_create_commit :queue_property_key_discovery, if: :has_properties?
  end

  private

  def queue_attribution_calculation
    Conversions::AttributionCalculationJob.perform_later(id)
  end

  def queue_property_key_discovery
    Conversions::PropertyKeyDiscoveryJob.perform_later(account_id)
  end

  def has_properties?
    properties.present? && properties != {}
  end
end
