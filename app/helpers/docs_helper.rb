module DocsHelper
  def render_markdown(text)
    markdown_renderer.render(text).html_safe
  end

  # Render multi-language code tabs (Stripe-style)
  #
  # Usage in ERB:
  # <%= code_tabs({
  #   ruby: { label: 'Ruby', code: 'puts "Hello"' },
  #   python: { label: 'Python', code: 'print("Hello")' },
  #   php: { label: 'PHP', code: 'echo "Hello";' },
  #   curl: { label: 'cURL', code: 'curl https://...' }
  # }) %>
  def code_tabs(examples, default: nil)
    languages = examples.keys
    default_lang = default || languages.first

    render partial: 'docs/shared/code_tabs', locals: {
      examples: examples,
      languages: languages,
      default_lang: default_lang
    }
  end

  # Common code examples for documentation
  def api_key_configuration_example
    code_tabs(filter_live_examples({
      ruby: {
        label: 'Ruby',
        syntax: 'ruby',
        code: <<~CODE
          # config/initializers/mbuzz.rb
          Mbuzz.init(
            api_key: ENV['MBUZZ_API_KEY'],
            debug: Rails.env.development?
          )
        CODE
      },
      nodejs: {
        label: 'Node.js',
        syntax: 'javascript',
        code: <<~CODE
          // app.js or server.js
          const mbuzz = require('mbuzz');

          mbuzz.init({
            apiKey: process.env.MBUZZ_API_KEY,
            debug: process.env.NODE_ENV === 'development'
          });
        CODE
      },
      curl: {
        label: 'REST API',
        syntax: 'bash',
        code: <<~CODE
          # Set your API key as environment variable
          export MBUZZ_API_KEY=sk_test_your_key_here

          # Use in Authorization header
          curl -H "Authorization: Bearer $MBUZZ_API_KEY" \\
               https://mbuzz.co/api/v1/events
        CODE
      }
    }))
  end

  def api_key_usage_example
    code_tabs(filter_live_examples({
      ruby: {
        label: 'Ruby',
        syntax: 'ruby',
        code: <<~CODE
          # Automatically handled by gem
          Mbuzz.init(api_key: ENV['MBUZZ_API_KEY'])

          # Gem adds header to all requests:
          # Authorization: Bearer sk_test_...
        CODE
      },
      nodejs: {
        label: 'Node.js',
        syntax: 'javascript',
        code: <<~CODE
          // Automatically handled by SDK
          const mbuzz = require('mbuzz');
          mbuzz.init({ apiKey: process.env.MBUZZ_API_KEY });

          // SDK adds header to all requests:
          // Authorization: Bearer sk_test_...
        CODE
      },
      curl: {
        label: 'cURL',
        syntax: 'bash',
        code: <<~CODE
          curl -X POST #{api_v1_events_url} \\
            -H "Authorization: Bearer sk_test_your_key_here" \\
            -H "Content-Type: application/json" \\
            -d '{"event_type": "page_view", "visitor_id": "abc123..."}'
        CODE
      }
    }), default: :curl)
  end

  def track_event_example
    code_tabs(filter_live_examples({
      ruby: {
        label: 'Ruby',
        syntax: 'ruby',
        code: <<~CODE
          # Track user interactions
          Mbuzz.event("page_view", url: "/pricing")
          Mbuzz.event("add_to_cart", product_id: "SKU-123", price: 49.99)
        CODE
      },
      nodejs: {
        label: 'Node.js',
        syntax: 'javascript',
        code: <<~CODE
          // Track user interactions
          mbuzz.event('page_view', { url: '/pricing' });
          mbuzz.event('add_to_cart', { productId: 'SKU-123', price: 49.99 });
        CODE
      },
      curl: {
        label: 'REST API',
        syntax: 'bash',
        code: <<~CODE
          curl -X POST https://mbuzz.co/api/v1/events \\
            -H "Authorization: Bearer $MBUZZ_API_KEY" \\
            -H "Content-Type: application/json" \\
            -d '{
              "events": [{
                "event_type": "page_view",
                "visitor_id": "abc123...",
                "properties": { "url": "/pricing" }
              }]
            }'
        CODE
      }
    }), default: :ruby)
  end

  private

  # Filter code examples to only include live SDKs
  # Maps example keys to SDK registry keys
  SDK_KEY_MAP = {
    ruby: :ruby,
    nodejs: :nodejs,
    python: :python,
    php: :php,
    curl: :rest_api
  }.freeze

  # Always show these regardless of SDK status (API reference)
  ALWAYS_SHOW = %i[curl].freeze

  def filter_live_examples(examples)
    examples.select do |key, _|
      ALWAYS_SHOW.include?(key) || sdk_live?(SDK_KEY_MAP[key])
    end
  end

  def sdk_live?(sdk_key)
    return true if sdk_key.nil?

    sdk = SdkRegistry.find(sdk_key.to_s)
    sdk&.live?
  end

  def markdown_renderer
    @markdown_renderer ||= Redcarpet::Markdown.new(
      html_renderer_with_syntax_highlighting,
      markdown_options
    )
  end

  def html_renderer_with_syntax_highlighting
    SyntaxHighlightRenderer.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" },
      with_toc_data: true
    )
  end

  def markdown_options
    {
      fenced_code_blocks: true,
      autolink: true,
      tables: true,
      strikethrough: true,
      space_after_headers: true,
      no_intra_emphasis: true,
      superscript: true
    }
  end

  # Custom renderer with Rouge syntax highlighting
  class SyntaxHighlightRenderer < Redcarpet::Render::HTML
    def block_code(code, language)
      language ||= 'text'

      # Use Rouge for syntax highlighting
      lexer = Rouge::Lexer.find_fancy(language, code) || Rouge::Lexers::PlainText.new
      formatter = Rouge::Formatters::HTML.new

      highlighted_code = formatter.format(lexer.lex(code))

      <<~HTML
        <div class="code-block not-prose my-6">
          <div class="code-header bg-slate-800 text-slate-400 text-xs font-medium px-4 py-2 rounded-t-lg border-b border-slate-700">
            #{language}
          </div>
          <div class="code-content bg-slate-900 rounded-b-lg overflow-x-auto">
            <pre class="p-4 m-0"><code class="language-#{language} text-sm leading-relaxed"><div class="highlight">#{highlighted_code}</div></code></pre>
          </div>
        </div>
      HTML
    end
  end
end
