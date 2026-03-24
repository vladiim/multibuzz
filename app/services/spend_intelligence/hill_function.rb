# frozen_string_literal: true

module SpendIntelligence
  module HillFunction
    # Revenue(spend) = K * spend^S / (spend^S + EC50^S)
    def self.evaluate(spend, k, s, ec50)
      return 0.0 if spend <= 0 || ec50 <= 0

      spend_s = spend**s
      k * spend_s / (spend_s + ec50**s)
    end

    # mROAS(spend) = K * S * EC50^S * spend^(S-1) / (spend^S + EC50^S)^2
    def self.derivative(spend, k, s, ec50)
      return nil if spend <= 0 || ec50 <= 0

      spend_s = spend**s
      ec50_s = ec50**s
      denominator = (spend_s + ec50_s)**2
      return nil if denominator.zero?

      (k * s * ec50_s * spend**(s - 1) / denominator).round(4)
    end
  end
end
