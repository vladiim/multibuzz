# frozen_string_literal: true

module AML
  class Executor
    def initialize(dsl_code:, touchpoints:, conversion_time:, conversion_value:)
      @dsl_code = dsl_code
      @touchpoints = touchpoints
      @conversion_time = conversion_time
      @conversion_value = conversion_value
    end

    def call
      validate_security!
      context.execute(&block)
    end

    private

    attr_reader :dsl_code, :touchpoints, :conversion_time, :conversion_value

    def validate_security!
      analyzer.analyze!
    end

    def analyzer
      @analyzer ||= Security::ASTAnalyzer.new(dsl_code)
    end

    def context
      @context ||= Sandbox::Context.new(
        touchpoints: touchpoints,
        conversion_time: conversion_time,
        conversion_value: conversion_value
      )
    end

    def block
      @block ||= build_block
    end

    def build_block
      eval("proc { #{dsl_code} }", TOPLEVEL_BINDING, "(aml)", 1)
    rescue ::SyntaxError => e
      raise ::AML::SyntaxError.new(e.message)
    end
  end
end
