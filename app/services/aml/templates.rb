# frozen_string_literal: true

module AML
  module Templates
    DEFINITIONS = {
      first_touch: {
        name: "First Touch",
        description: "100% credit to the first touchpoint in the journey",
        code: <<~AML
          within_window %{lookback_days}.days do
            apply 1.0, to: touchpoints.first
          end
        AML
      },

      last_touch: {
        name: "Last Touch",
        description: "100% credit to the last touchpoint before conversion",
        code: <<~AML
          within_window %{lookback_days}.days do
            apply 1.0, to: touchpoints.last
          end
        AML
      },

      linear: {
        name: "Linear",
        description: "Equal credit distributed across all touchpoints",
        code: <<~AML
          within_window %{lookback_days}.days do
            apply 1.0, to: touchpoints, distribute: :equal
          end
        AML
      },

      time_decay: {
        name: "Time Decay",
        description: "Exponentially more credit to touchpoints closer to conversion",
        code: <<~AML
          within_window %{lookback_days}.days do
            time_decay half_life: 7.days
          end
        AML
      },

      u_shaped: {
        name: "U-Shaped (Position Based)",
        description: "40% first, 40% last, 20% distributed to middle touchpoints",
        code: <<~AML
          within_window %{lookback_days}.days do
            apply 0.4, to: touchpoints.first
            apply 0.4, to: touchpoints.last
            apply 0.2, to: touchpoints[1..-2], distribute: :equal
          end
        AML
      },

      participation: {
        name: "Participation",
        description: "Equal credit to every touchpoint that participated (sums to 100%)",
        code: <<~AML
          within_window %{lookback_days}.days do
            apply 1.0, to: touchpoints, distribute: :equal
          end
        AML
      }
    }.freeze

    class << self
      def generate(algorithm, lookback_days: 30)
        template = DEFINITIONS.fetch(algorithm.to_sym)
        format(template[:code], lookback_days: lookback_days)
      end

      def all
        DEFINITIONS.map do |key, template|
          {
            key: key,
            name: template[:name],
            description: template[:description]
          }
        end
      end

      def find(key)
        template = DEFINITIONS[key.to_sym]
        return nil unless template

        {
          key: key.to_sym,
          name: template[:name],
          description: template[:description]
        }
      end
    end
  end
end
