# frozen_string_literal: true

module AML
  module Security
    class Whitelist
      ALLOWED_ARRAY_METHODS = %w[
        [] []=
        length size count empty? any? all? none?
        first last
        select reject find find_all find_index
        map collect
        each each_with_index
        include?
        - + &
        slice
        sum
        min max minmax
        sort sort_by
        reverse
        take drop
        compact
        uniq
        flatten
        zip
      ].freeze

      ALLOWED_STRING_METHODS = %w[
        == != =~ !~
        start_with? starts_with?
        end_with? ends_with?
        include?
        match?
        upcase downcase capitalize
        strip lstrip rstrip
        length size
        empty?
        split
        gsub sub
        [] slice
        to_s to_sym
      ].freeze

      ALLOWED_NUMERIC_METHODS = %w[
        + - * / ** %
        +@ -@
        > < >= <= == != <=>
        abs floor ceil round truncate
        to_i to_f to_s
        between?
        positive? negative? zero?
        even? odd?
        divmod
        fdiv
      ].freeze

      ALLOWED_TIME_METHODS = %w[
        > < >= <= == != <=> between?
        + -
        year month day hour min sec wday yday
        monday? tuesday? wednesday? thursday? friday? saturday? sunday?
        beginning_of_day end_of_day
        beginning_of_week end_of_week
        beginning_of_month end_of_month
        to_i to_f to_s to_date to_datetime
        iso8601
        strftime
      ].freeze

      ALLOWED_DURATION_METHODS = %w[
        day days
        week weeks
        month months
        year years
        hour hours
        minute minutes
        second seconds
        ago from_now since until
        to_i to_f
        + - * /
      ].freeze

      ALLOWED_HASH_METHODS = %w[
        [] fetch
        key? has_key? include? member?
        keys values
        empty? any?
        length size count
        dig
        slice
        to_a
      ].freeze

      ALLOWED_MATH_CONSTANTS = %w[
        Math
      ].freeze

      ALLOWED_MATH_METHODS = %w[
        exp log log10 log2
        sqrt cbrt
        sin cos tan
        asin acos atan atan2
        sinh cosh tanh
        asinh acosh atanh
        hypot
        erf erfc
        gamma lgamma
      ].freeze

      ALLOWED_DSL_METHODS = %w[
        within_window
        apply
        time_decay
        normalize!
        touchpoints
        conversion_time
        conversion_value
        stages
        stage
      ].freeze

      ALLOWED_CONTROL_FLOW = %w[
        if elsif else end
        unless
        case when then
        do
      ].freeze

      # Safe built-in methods
      ALLOWED_SAFE_METHODS = %w[
        nil?
        present?
        blank?
        is_a?
        kind_of?
        respond_to?
        to_s
        to_i
        to_f
        to_a
        to_h
        inspect
        hash
        eql?
        equal?
        !
        !=
        ==
        <=>
        ===
      ].freeze

      FORBIDDEN_METHODS = %w[
        eval instance_eval class_eval module_eval
        exec system spawn fork
        ` send __send__ public_send
        method_missing respond_to_missing?
        define_method define_singleton_method
        undef_method remove_method
        alias_method
        const_get const_set const_missing const_defined?
        remove_const
        class_variable_get class_variable_set
        instance_variable_get instance_variable_set
        extend include prepend
        require require_relative load autoload
        open
        binding
        caller caller_locations
        exit exit! abort
        raise fail throw catch
        sleep
        at_exit
        trap
        set_trace_func
        method __method__ __callee__
        singleton_class
        freeze frozen?
        taint untaint tainted?
        trust untrust untrusted?
        object_id __id__
        class
        superclass
        ancestors
        popen
      ].freeze

      FORBIDDEN_CONSTANTS = %w[
        File Dir IO FileUtils Pathname Tempfile
        Socket TCPSocket UDPSocket UNIXSocket
        Net HTTP HTTPS URI OpenURI
        Process Kernel Object Module Class
        Thread Fiber Mutex ConditionVariable Queue SizedQueue
        ObjectSpace GC
        Proc Method UnboundMethod
        Binding
        ENV ARGV ARGF
        DATA STDIN STDOUT STDERR
        Marshal YAML JSON
        Gem Bundler
        Rails ActiveRecord ActiveSupport
        DRb
        Ripper Parser
        RubyVM
        TracePoint
        Open3 PTY
      ].freeze

      FORBIDDEN_GLOBALS = %w[
        $0 $PROGRAM_NAME
        $: $LOAD_PATH
        $" $LOADED_FEATURES
        $; $-F $FS $FIELD_SEPARATOR
        $, $OFS $OUTPUT_FIELD_SEPARATOR
        $/ $-0 $RS $INPUT_RECORD_SEPARATOR
        $\\ $ORS $OUTPUT_RECORD_SEPARATOR
        $. $NR $INPUT_LINE_NUMBER
        $_ $LAST_READ_LINE
        $> $DEFAULT_OUTPUT
        $< $DEFAULT_INPUT
        $$ $PID $PROCESS_ID
        $? $CHILD_STATUS
        $! $ERROR_INFO
        $@ $ERROR_POSITION
        $~ $MATCH
        $& $MATCH
        $` $PREMATCH
        $' $POSTMATCH
        $+ $LAST_PAREN_MATCH
        $= $IGNORECASE
        $* $ARGV
        $SAFE
        $-d $DEBUG
        $-v $VERBOSE
        $-w $-W
        $stderr $stdout $stdin
      ].freeze

      class << self
        def allowed_method?(method_name)
          method_str = method_name.to_s
          all_allowed_methods.include?(method_str)
        end

        def forbidden_method?(method_name)
          method_str = method_name.to_s
          FORBIDDEN_METHODS.include?(method_str)
        end

        def forbidden_constant?(const_name)
          const_str = const_name.to_s
          FORBIDDEN_CONSTANTS.include?(const_str)
        end

        def forbidden_global?(global_name)
          global_str = global_name.to_s
          FORBIDDEN_GLOBALS.include?(global_str)
        end

        def allowed_constant?(const_name)
          const_str = const_name.to_s
          ALLOWED_MATH_CONSTANTS.include?(const_str)
        end

        private

        def all_allowed_methods
          @all_allowed_methods ||= [
            ALLOWED_ARRAY_METHODS,
            ALLOWED_STRING_METHODS,
            ALLOWED_NUMERIC_METHODS,
            ALLOWED_TIME_METHODS,
            ALLOWED_DURATION_METHODS,
            ALLOWED_HASH_METHODS,
            ALLOWED_MATH_METHODS,
            ALLOWED_DSL_METHODS,
            ALLOWED_SAFE_METHODS
          ].flatten.to_set
        end
      end
    end
  end
end
