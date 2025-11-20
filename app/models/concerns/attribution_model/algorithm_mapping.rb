# frozen_string_literal: true

module AttributionModel::AlgorithmMapping
  extend ActiveSupport::Concern

  ALGORITHM_CLASSES = {
    first_touch: Attribution::Algorithms::FirstTouch,
    last_touch: Attribution::Algorithms::LastTouch,
    linear: Attribution::Algorithms::Linear
  }.freeze

  def algorithm_class
    ALGORITHM_CLASSES.fetch(algorithm.to_sym) do
      raise ArgumentError, "Unknown algorithm: #{algorithm}"
    end
  end
end
