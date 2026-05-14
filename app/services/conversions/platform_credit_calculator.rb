# frozen_string_literal: true

# Pure function: given a conversion and a destination, returns the
# fraction of the conversion's attribution credit (under the
# destination's chosen attribution model) that this platform earned.
#
#   share = sum(credits where session matches platform) / sum(all credits for the model)
#
# Returns 0.0 when the conversion has no credits for the destination's
# attribution_model, or when no credited touchpoint matches the
# platform's source predicate. Used by Phase 6's OutboundConversionJob
# as the gate: if `share < destination.minimum_credit_threshold` the
# job records `skipped_no_credit` and never calls the dispatcher.
module Conversions
  class PlatformCreditCalculator
    PLATFORM_MATCHERS = {
      meta_capi: AdDestinations::Meta::SourceMatcher
    }.freeze

    def initialize(conversion, destination)
      @conversion = conversion
      @destination = destination
    end

    def call
      return 0.0 if total_credit.zero?

      platform_credit / total_credit
    end

    private

    attr_reader :conversion, :destination

    def total_credit
      @total_credit ||= credits_for_model.sum(&:credit).to_f
    end

    def platform_credit
      @platform_credit ||= matching_credits.sum(&:credit).to_f
    end

    def matching_credits
      credits_for_model.select { |credit| matcher.matches?(session_for(credit)) }
    end

    def credits_for_model
      @credits_for_model ||= conversion.attribution_credits.where(attribution_model: destination.attribution_model).to_a
    end

    def session_for(credit)
      sessions_by_id[credit.session_id]
    end

    def sessions_by_id
      @sessions_by_id ||= conversion.account.sessions.where(id: credits_for_model.map(&:session_id)).index_by(&:id)
    end

    def matcher
      PLATFORM_MATCHERS.fetch(destination.platform.to_sym)
    end
  end
end
