# frozen_string_literal: true

module AML
  module Sandbox
    class CreditAssigner
      def initialize(touchpoints:, ledger:)
        @touchpoints = touchpoints
        @ledger = ledger
      end

      def apply_fixed(credit:, target:)
        indices = resolve_indices(target)
        return if indices.empty?

        indices.each { |i| @ledger[i] = credit }
      end

      def apply_distributed(credit:, targets:)
        indices = resolve_indices(targets)
        return if indices.empty?

        credit_per_target = credit / indices.length
        indices.each { |i| @ledger[i] = credit_per_target }
      end

      def apply_block(targets:, &block)
        indices = resolve_indices(targets || @touchpoints)
        return if indices.empty?

        indices.each do |i|
          @ledger[i] = block.call(@touchpoints[i], i)
        end
      end

      private

      def resolve_indices(target)
        IndexResolver.new(@touchpoints).resolve(target)
      end
    end

    class IndexResolver
      def initialize(touchpoints)
        @touchpoints = touchpoints
        @length = touchpoints.length
      end

      def resolve(target)
        case target
        when SafeTouchpoint then resolve_touchpoint(target)
        when TouchpointCollection then resolve_collection(target)
        when Array then resolve_array(target)
        when Range then resolve_range(target)
        when Integer then resolve_integer(target)
        when nil then all_indices
        else []
        end
      end

      private

      def resolve_touchpoint(touchpoint)
        index = @touchpoints.index(touchpoint)
        index ? [index] : []
      end

      def resolve_collection(collection)
        collection.map { |tp| @touchpoints.index(tp) }.compact.uniq
      end

      def resolve_array(array)
        array.flat_map { |t| resolve(t) }.compact.uniq
      end

      def resolve_range(range)
        start_idx = normalize_index(range.begin) || 0
        end_idx = normalize_index(range.end) || (@length - 1)
        end_idx -= 1 if range.exclude_end?

        return [] if start_idx > end_idx || start_idx >= @length

        (start_idx..end_idx).select { |i| i >= 0 && i < @length }
      end

      def resolve_integer(idx)
        normalized = normalize_index(idx)
        normalized && normalized >= 0 && normalized < @length ? [normalized] : []
      end

      def all_indices
        (0...@length).to_a
      end

      def normalize_index(idx)
        return nil if idx.nil?

        idx < 0 ? @length + idx : idx
      end
    end
  end
end
