# frozen_string_literal: true

# Narrow exception class raised by ad-destination dispatchers after they
# persist a transient or auth-failure status to a ConversionDispatch row.
# OutboundConversionJob's retry_on listens for this class specifically so
# only platform-side retryable failures trigger Solid Queue retries.
# RecordInvalid, NoMethodError, etc. surface as permanent failures
# rather than being silently swallowed as "transient".
module AdDestinations
  module Errors
    class RetryableDispatchError < StandardError; end
  end
end
