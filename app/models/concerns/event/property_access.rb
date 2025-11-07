module Event::PropertyAccess
  extend ActiveSupport::Concern

  def utm_source
    properties["utm_source"]
  end

  def utm_medium
    properties["utm_medium"]
  end

  def utm_campaign
    properties["utm_campaign"]
  end

  def utm_content
    properties["utm_content"]
  end

  def utm_term
    properties["utm_term"]
  end

  def url
    properties["url"]
  end

  def referrer
    properties["referrer"]
  end
end
