xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.rss version: "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom" do
  xml.channel do
    xml.title "MTA Academy — mbuzz"
    xml.description "Long-form articles on multi-touch attribution, model selection, server-side tracking, ROAS measurement, and budget allocation. Practitioner-focused, source-cited, model-honest."
    xml.link academy_url
    xml.language "en-us"
    xml.lastBuildDate(@articles.first&.last_updated&.to_time&.rfc2822 || Time.now.rfc2822)
    xml.tag!("atom:link", href: academy_rss_url, rel: "self", type: "application/rss+xml")

    @articles.each do |article|
      xml.item do
        xml.title article.title
        xml.description article.description
        xml.pubDate(article.published_at.to_time.rfc2822) if article.published_at
        xml.link article_url(article.slug)
        xml.guid article_url(article.slug), isPermaLink: "true"
        xml.author "noreply@mbuzz.co (#{article.author})"
        xml.category article.section.to_s.titleize
      end
    end
  end
end
