# frozen_string_literal: true

module Text
  class LevenshteinMatcher
    DEFAULT_THRESHOLD = 2

    def initialize(candidates, threshold: DEFAULT_THRESHOLD)
      @candidates = candidates
      @threshold = threshold
    end

    def find_match(value)
      candidates.min_by { |c| distance(value, c) }
        .then { |match| within_threshold?(value, match) ? match : nil }
    end

    def within_threshold?(s1, s2)
      distance(s1, s2) <= threshold
    end

    def distance(s1, s2)
      self.class.distance(s1, s2)
    end

    class << self
      def distance(s1, s2)
        return s2.length if s1.empty?
        return s1.length if s2.empty?

        compute_distance(s1, s2)
      end

      private

      def compute_distance(s1, s2)
        prev_row = (0..s2.length).to_a

        s1.each_char.with_index(1) do |char1, i|
          curr_row = [i]
          s2.each_char.with_index(1) do |char2, j|
            curr_row << min_cost(prev_row, curr_row, i, j, char1 == char2)
          end
          prev_row = curr_row
        end

        prev_row.last
      end

      def min_cost(prev_row, curr_row, _i, j, match)
        [
          curr_row[j - 1] + 1,          # insertion
          prev_row[j] + 1,               # deletion
          prev_row[j - 1] + (match ? 0 : 1)  # substitution
        ].min
      end
    end

    private

    attr_reader :candidates, :threshold
  end
end
