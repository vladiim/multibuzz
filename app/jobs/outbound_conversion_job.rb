# frozen_string_literal: true

# Thin Solid Queue wrapper. All logic lives in
# Conversions::OutboundDispatchService.
#
# retry_on listens narrowly for AdDestinations::Errors::RetryableDispatchError
# (raised by dispatchers when they persist token_failed or failed_transient
# rows). RecordInvalid / NoMethodError / etc. propagate up as job failures
# rather than being silently retried as "transient".
class OutboundConversionJob < ApplicationJob
  queue_as :default

  retry_on AdDestinations::Errors::RetryableDispatchError,
    wait: :polynomially_longer, attempts: 3

  def perform(conversion_id, destination_id)
    Conversions::OutboundDispatchService.new(
      Conversion.find(conversion_id),
      ConversionDestination.find(destination_id)
    ).call
  end
end
