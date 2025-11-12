module DocsHelper
  def render_markdown(text)
    markdown_renderer.render(text).html_safe
  end

  private

  def markdown_renderer
    @markdown_renderer ||= Redcarpet::Markdown.new(
      html_renderer,
      markdown_options
    )
  end

  def html_renderer
    Redcarpet::Render::HTML.new(
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
end
