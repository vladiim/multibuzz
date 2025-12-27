module ArticlesHelper
  include DocsHelper

  def render_article_content(article)
    template = ERB.new(article.content)
    markdown_content = template.result(binding)
    render_markdown(markdown_content)
  end

  def render_tldr(text)
    return "" unless text.present?

    content_tag(:div, class: "bg-blue-50 border-l-4 border-blue-500 p-4 my-6 not-prose") do
      content_tag(:p, text, class: "text-blue-900 font-medium")
    end
  end

  def render_key_takeaways(takeaways)
    return "" if takeaways.blank?

    content_tag(:div, class: "bg-gray-50 rounded-lg p-6 my-8 not-prose") do
      content_tag(:h3, "Key Takeaways", class: "font-semibold text-gray-900 mb-4") +
      content_tag(:ul, class: "space-y-2") do
        safe_join(takeaways.map { |t| takeaway_item(t) })
      end
    end
  end

  def render_faq(faq_items)
    return "" if faq_items.blank?

    content_tag(:div, class: "space-y-6 my-8") do
      safe_join(faq_items.map { |item| faq_item(item) })
    end
  end

  def render_info_box(&block)
    content_tag(:div, class: "bg-blue-50 border border-blue-200 rounded-lg p-4 my-6 not-prose text-blue-900") do
      capture(&block)
    end
  end

  def render_warning_box(&block)
    content_tag(:div, class: "bg-amber-50 border border-amber-200 rounded-lg p-4 my-6 not-prose text-amber-900") do
      capture(&block)
    end
  end

  def render_diagram(path, alt:, caption: nil)
    content_tag(:figure, class: "my-8") do
      image_tag(path, alt: alt, class: "w-full rounded-lg shadow-sm") +
      (caption ? content_tag(:figcaption, caption, class: "text-center text-sm text-gray-500 mt-2") : "".html_safe)
    end
  end

  private

  def takeaway_item(text)
    content_tag(:li, class: "flex items-start gap-3") do
      content_tag(:span, checkmark_icon, class: "text-green-600 font-bold") +
      content_tag(:span, text, class: "text-gray-700")
    end
  end

  def faq_item(item)
    question = item["q"] || item[:q] || item["question"] || item[:question]
    answer = item["a"] || item[:a] || item["answer"] || item[:answer]

    content_tag(:details, class: "group border-b border-gray-200 pb-4") do
      content_tag(:summary, class: "cursor-pointer font-medium text-gray-900 list-none flex justify-between items-center") do
        sanitize(question.to_s) +
        content_tag(:span, chevron_icon, class: "text-gray-400 group-open:rotate-180 transition-transform")
      end +
      content_tag(:div, answer, class: "mt-3 text-gray-600")
    end
  end

  def checkmark_icon
    "&#10003;".html_safe
  end

  def chevron_icon
    "&#9660;".html_safe
  end
end
