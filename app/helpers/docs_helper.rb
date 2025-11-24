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

  private

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
            <pre class="p-4 m-0"><code class="language-#{language} text-sm leading-relaxed">#{highlighted_code}</code></pre>
          </div>
        </div>
      HTML
    end
  end
end
