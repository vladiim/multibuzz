# frozen_string_literal: true

module AML
  module Sandbox
    class TouchpointCollection
      include Enumerable

      def initialize(raw_touchpoints)
        @touchpoints = raw_touchpoints.map { |tp| wrap(tp) }
      end

      def each(&block)
        @touchpoints.each(&block)
      end

      def [](index_or_range)
        case index_or_range
        when Integer
          @touchpoints[index_or_range]
        when Range
          self.class.from_array(@touchpoints[index_or_range] || [])
        end
      end

      def length
        @touchpoints.length
      end

      alias size length
      alias count length

      def first
        @touchpoints.first
      end

      def last
        @touchpoints.last
      end

      def empty?
        @touchpoints.empty?
      end

      def any?(&block)
        block ? @touchpoints.any?(&block) : @touchpoints.any?
      end

      def select(&block)
        self.class.from_array(@touchpoints.select(&block))
      end

      def reject(&block)
        self.class.from_array(@touchpoints.reject(&block))
      end

      def find(&block)
        @touchpoints.find(&block)
      end

      def map(&block)
        @touchpoints.map(&block)
      end

      def each_with_index(&block)
        @touchpoints.each_with_index(&block)
      end

      def -(other)
        other_set = Array(other).to_set
        self.class.from_array(@touchpoints.reject { |tp| other_set.include?(tp) })
      end

      def sum(&block)
        @touchpoints.sum(&block)
      end

      def index(touchpoint)
        @touchpoints.index(touchpoint)
      end

      def to_a
        @touchpoints.dup
      end

      def self.from_array(touchpoints)
        collection = allocate
        collection.instance_variable_set(:@touchpoints, touchpoints)
        collection
      end

      private

      def wrap(tp)
        SafeTouchpoint.new(
          session_id: tp[:session_id],
          channel: tp[:channel],
          occurred_at: tp[:occurred_at],
          event_type: tp[:event_type],
          properties: tp[:properties]
        )
      end
    end
  end
end
