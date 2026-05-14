# frozen_string_literal: true

# Thin Solid Queue wrapper. All logic lives in
# Conversions::OutboundDispatchService.
class OutboundConversionJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(conversion_id, destination_id)
    Conversions::OutboundDispatchService.new(
      Conversion.find(conversion_id),
      ConversionDestination.find(destination_id)
    ).call
  end
end
