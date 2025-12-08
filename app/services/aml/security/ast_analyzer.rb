# frozen_string_literal: true

require "parser/current"

module AML
  module Security
    class ASTAnalyzer
      NODE_CHECKERS = {
        send: :check_send,
        const: :check_const,
        xstr: :check_backtick,
        gvar: :check_global_variable,
        casgn: :check_constant_assignment,
        class: :check_class_definition,
        module: :check_class_definition,
        def: :check_method_definition,
        defs: :check_method_definition
      }.freeze

      FORBIDDEN_SEND_METHODS = %w[class superclass ancestors].to_set.freeze

      def initialize(code)
        @code = code
      end

      def analyze!
        walk(ast)
        raise_if_errors!
        true
      end

      def valid?
        analyze!
      rescue AML::SecurityError
        false
      end

      private

      attr_reader :code

      def ast
        @ast ||= parse_code
      end

      def errors
        @errors ||= []
      end

      def parse_code
        # Suppress diagnostic output from parser gem
        buffer = Parser::Source::Buffer.new("(string)")
        buffer.source = code
        builder = Parser::Builders::Default.new
        parser = Parser::CurrentRuby.new(builder)
        parser.diagnostics.consumer = ->(diagnostic) {} # Silence diagnostics
        parser.parse(buffer)
      rescue ::Parser::SyntaxError => e
        raise AML::SyntaxError.new(e.message, line: e.diagnostic&.location&.line || 1)
      end

      def walk(node)
        return unless node.is_a?(::Parser::AST::Node)

        check_node(node)
        node.children.each { |child| walk(child) }
      end

      def check_node(node)
        checker = NODE_CHECKERS[node.type]
        send(checker, node) if checker
      end

      # Node checkers

      def check_send(node)
        receiver, method_name, * = node.children
        method_str = method_name.to_s

        return add_error("Forbidden method: #{method_name}", node) if Whitelist.forbidden_method?(method_name)
        return add_error("Forbidden method: #{method_str}", node) if FORBIDDEN_SEND_METHODS.include?(method_str)

        check_receiver_constant(receiver, node) if receiver
      end

      def check_const(node)
        const_name = extract_const_name(node)
        return unless const_name
        return if Whitelist.allowed_constant?(const_name)

        add_error("Forbidden constant: #{const_name}", node) if Whitelist.forbidden_constant?(const_name)
      end

      def check_backtick(node)
        add_error("Backtick command execution not allowed", node)
      end

      def check_global_variable(node)
        var_name = node.children.first.to_s
        add_error("Global variable access not allowed: #{var_name}", node)
      end

      def check_constant_assignment(node)
        add_error("Constant assignment not allowed", node)
      end

      def check_class_definition(node)
        add_error("Class/module definition not allowed", node)
      end

      def check_method_definition(node)
        add_error("Method definition not allowed", node)
      end

      # Helpers

      def check_receiver_constant(receiver, node)
        return unless receiver.is_a?(::Parser::AST::Node) && receiver.type == :const

        const_name = extract_const_name(receiver)
        return unless const_name

        add_error("Forbidden constant: #{const_name}", node) if Whitelist.forbidden_constant?(const_name)
      end

      def extract_const_name(node)
        return unless node.is_a?(::Parser::AST::Node)
        return unless node.type == :const

        scope, name = node.children
        return name.to_s if scope.nil?

        parent = extract_const_name(scope)
        parent ? "#{parent}::#{name}" : name.to_s
      end

      def add_error(message, node)
        errors << build_error(message, node)
      end

      def build_error(message, node)
        {
          message: message,
          line: node.loc&.line,
          column: node.loc&.column
        }
      end

      def raise_if_errors!
        return if errors.empty?

        first = errors.first
        raise AML::SecurityError.new(
          first[:message],
          line: first[:line],
          column: first[:column]
        )
      end
    end
  end
end
