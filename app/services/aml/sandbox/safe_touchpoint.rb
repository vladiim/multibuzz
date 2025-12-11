# frozen_string_literal: true

module AML
  module Sandbox
    class SafeTouchpoint
      ALLOWED_METHODS = %i[
        session_id channel occurred_at event_type properties
        == != eql? hash
      ].to_set.freeze

      FORBIDDEN_METHODS = %i[
        send __send__ public_send
        instance_eval class_eval
        instance_variable_get instance_variable_set
        method define_method
        class singleton_class
      ].to_set.freeze

      def initialize(session_id:, channel:, occurred_at:, event_type: nil, properties: {})
        @session_id = session_id
        @channel = channel.to_s.freeze
        @occurred_at = occurred_at
        @event_type = event_type&.to_s&.freeze
        @properties = SafeHash.new(properties || {})
      end

      attr_reader :session_id, :channel, :occurred_at, :event_type, :properties

      def ==(other)
        other.is_a?(SafeTouchpoint) && session_id == other.session_id
      end

      def eql?(other)
        self == other
      end

      def hash
        session_id.hash
      end

      def method_missing(method_name, *args, &block)
        raise ::AML::SecurityError.new("Method not allowed on touchpoint: #{method_name}")
      end

      def respond_to_missing?(method_name, include_private = false)
        false
      end

      # Block dangerous methods inherited from Object
      # Suppress warnings for intentional redefinition (sandbox security)
      original_verbose = $VERBOSE
      $VERBOSE = nil
      FORBIDDEN_METHODS.each do |method_name|
        define_method(method_name) do |*args, &block|
          raise ::AML::SecurityError.new("Method not allowed on touchpoint: #{method_name}")
        end
      end
      $VERBOSE = original_verbose
    end

    class SafeHash
      ALLOWED_METHODS = %i[
        [] fetch dig
        key? has_key? include? member?
        keys values
        empty? any? length size count
        to_a to_h
        == != eql?
      ].to_set.freeze

      def initialize(hash)
        @hash = hash.transform_keys(&:to_s).freeze
      end

      def [](key)
        @hash[key.to_s]
      end

      def fetch(key, *args, &block)
        @hash.fetch(key.to_s, *args, &block)
      end

      def dig(*keys)
        @hash.dig(*keys.map(&:to_s))
      end

      def key?(key)
        @hash.key?(key.to_s)
      end

      alias has_key? key?
      alias include? key?
      alias member? key?

      def keys
        @hash.keys
      end

      def values
        @hash.values
      end

      def empty?
        @hash.empty?
      end

      def any?(&block)
        block ? @hash.any?(&block) : @hash.any?
      end

      def length
        @hash.length
      end

      alias size length
      alias count length

      def to_a
        @hash.to_a
      end

      def to_h
        @hash.dup
      end

      def ==(other)
        case other
        when SafeHash then @hash == other.to_h
        when Hash then @hash == other.transform_keys(&:to_s)
        else false
        end
      end

      def eql?(other)
        self == other
      end

      def method_missing(method_name, *args, &block)
        raise ::AML::SecurityError.new("Method not allowed on properties: #{method_name}")
      end

      def respond_to_missing?(method_name, include_private = false)
        false
      end
    end
  end
end
