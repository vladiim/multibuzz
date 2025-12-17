# frozen_string_literal: true

module AttributionModel::AlgorithmMapping
  extend ActiveSupport::Concern

  ALGORITHM_CLASSES = {
    first_touch: Attribution::Algorithms::FirstTouch,
    last_touch: Attribution::Algorithms::LastTouch,
    linear: Attribution::Algorithms::Linear,
    time_decay: Attribution::Algorithms::TimeDecay,
    u_shaped: Attribution::Algorithms::UShaped,
    participation: Attribution::Algorithms::Participation,
    markov_chain: Attribution::Algorithms::MarkovChain
  }.freeze

  def algorithm_class
    raise ArgumentError, "algorithm not set for model '#{name}'" if algorithm.blank?

    ALGORITHM_CLASSES.fetch(algorithm.to_sym) do
      raise ArgumentError, "No implementation for algorithm: #{algorithm}"
    end
  end
end
