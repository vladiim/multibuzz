# frozen_string_literal: true

module AML
  module Sandbox
    class Context
      attr_reader :touchpoints, :conversion_time, :conversion_value, :lookback_window

      def initialize(touchpoints:, conversion_time:, conversion_value:)
        @touchpoints = TouchpointCollection.new(touchpoints)
        @conversion_time = conversion_time
        @conversion_value = conversion_value
        @segments = []
        @segment_blocks = []
      end

      def execute(&block)
        safe_eval(&block)
        finalize_segments if segments_defined?
        credit_ledger.validate!
        credit_ledger.to_a
      end

      # DSL Methods

      def within_window(duration_or_range, weight: nil, &block)
        return create_outer_window(duration_or_range, &block) unless lookback_window

        create_segment(duration_or_range, weight, &block)
      end

      def apply(credit = nil, to: nil, distribute: nil, &block)
        ensure_within_window!

        if block_given?
          credit_assigner.apply_block(targets: to, &block)
        elsif distribute == :equal
          credit_assigner.apply_distributed(credit: credit, targets: to)
        else
          credit_assigner.apply_fixed(credit: credit, target: to)
        end
      end

      def time_decay(half_life:)
        ensure_within_window!

        credits = TimeDecayCalculator.new(
          touchpoints: touchpoints,
          conversion_time: conversion_time,
          half_life: half_life
        ).call

        credit_ledger.replace(credits)
      end

      def normalize!
        credit_ledger.normalize!
      end

      def method_missing(method_name, *args, &block)
        raise ::AML::SecurityError.new("Method not allowed: #{method_name}")
      end

      def respond_to_missing?(method_name, include_private = false)
        false
      end

      # Block dangerous methods that exist on BasicObject/Kernel
      BLOCKED_METHODS = %i[
        instance_eval instance_exec
        send __send__ public_send
        class eval binding
        method __method__
      ].freeze

      # Suppress warnings for intentional redefinition of dangerous methods (sandbox security)
      original_verbose = $VERBOSE
      $VERBOSE = nil
      BLOCKED_METHODS.each do |method_name|
        define_method(method_name) do |*args, &block|
          raise ::AML::SecurityError.new("Method not allowed: #{method_name}")
        end
      end
      $VERBOSE = original_verbose

      private

      # Use BasicObject's instance_eval directly to bypass our blocked version
      ORIGINAL_INSTANCE_EVAL = ::BasicObject.instance_method(:instance_eval)

      def safe_eval(&block)
        ORIGINAL_INSTANCE_EVAL.bind(self).call(&block)
      end

      def credit_ledger
        @credit_ledger ||= CreditLedger.new(touchpoints.length)
      end

      def credit_assigner
        @credit_assigner ||= CreditAssigner.new(
          touchpoints: touchpoints,
          ledger: credit_ledger
        )
      end

      def ensure_within_window!
        return if lookback_window

        raise ::AML::ValidationError.new(
          "within_window must be called before apply",
          suggestion: "Add 'within_window 30.days do' at the start of your model"
        )
      end

      def create_outer_window(duration, &block)
        @lookback_window = duration
        safe_eval(&block) if block_given?
      end

      def create_segment(duration_or_range, weight, &block)
        segment = SegmentBuilder.new(
          range_or_duration: duration_or_range,
          weight: weight || 1.0,
          parent_touchpoints: touchpoints,
          conversion_time: conversion_time
        ).call

        @segments << segment
        @segment_blocks << block
      end

      def segments_defined?
        @segments.any?
      end

      def finalize_segments
        validate_segments
        execute_segments
        merge_segment_credits
      end

      def validate_segments
        SegmentValidator.new(
          segments: @segments,
          outer_window: lookback_window
        ).call
      end

      def execute_segments
        @segment_credits = @segments.zip(@segment_blocks).map do |segment, block|
          SegmentExecutor.new(
            segment: segment,
            conversion_time: conversion_time,
            conversion_value: conversion_value
          ).call(&block)
        end
      end

      def merge_segment_credits
        merged = SegmentCreditMerger.new(
          segments: @segments,
          segment_credits: @segment_credits,
          ledger_size: touchpoints.length
        ).call

        credit_ledger.replace(merged)
      end
    end
  end
end
