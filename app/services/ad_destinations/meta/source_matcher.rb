# frozen_string_literal: true

# Per-platform predicate: did this Session originate from a Meta paid
# touchpoint? Used by Conversions::PlatformCreditCalculator to decide
# how much of an attribution-model's credit goes to a Meta destination.
#
# v1 rule: presence of `fbclid` in the session's click_ids JSONB. Meta
# only ever sets fbclid in URL params for paid clicks (organic Facebook
# referrals are caught by referrer-based channel classification, not by
# click ID). Channel + source fallback can be layered later if needed.
module AdDestinations
  module Meta
    module SourceMatcher
      module_function

      def matches?(session)
        return false unless session&.click_ids

        session.click_ids.key?(ClickIdentifiers::FBCLID) || session.click_ids.key?(ClickIdentifiers::FBCLID.to_sym)
      end
    end
  end
end
