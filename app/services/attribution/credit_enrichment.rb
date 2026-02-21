# frozen_string_literal: true

module Attribution
  module CreditEnrichment
    private

    def compute_credits
      algorithm_credits
        .map { |credit| enrich_with_session_data(credit) }
        .map { |credit| add_revenue_credit(credit) }
    end

    def algorithm_credits
      @algorithm_credits ||= algorithm.call
    end

    def algorithm
      @algorithm ||= build_algorithm
    end

    def build_algorithm
      return build_probabilistic_model if probabilistic_model?

      attribution_model.algorithm_class.new(touchpoints)
    end

    def probabilistic_model?
      attribution_model.markov_chain? || attribution_model.shapley_value?
    end

    def build_probabilistic_model
      attribution_model.algorithm_class.new(
        touchpoints,
        conversion_paths: conversion_paths
      )
    end

    def account
      conversion.account
    end

    def enrich_with_session_data(credit)
      session = find_session(credit[:session_id])

      credit.merge(
        utm_source: utm_value(session, UtmKeys::SOURCE),
        utm_medium: utm_value(session, UtmKeys::MEDIUM),
        utm_campaign: utm_value(session, UtmKeys::CAMPAIGN)
      )
    end

    def find_session(session_id)
      sessions_map[session_id]
    end

    def sessions_map
      @sessions_map ||= begin
        session_ids = touchpoints.map { |t| t[:session_id] }
        account.sessions.where(id: session_ids).index_by(&:id)
      end
    end

    def utm_value(session, key)
      return nil unless session

      session.initial_utm&.dig(key) || session.initial_utm&.dig(key.to_sym)
    end

    def add_revenue_credit(credit)
      return credit unless conversion.revenue

      credit.merge(
        revenue_credit: (credit[:credit] * conversion.revenue).round(2)
      )
    end
  end
end
