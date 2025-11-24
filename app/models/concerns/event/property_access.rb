module Event::PropertyAccess
  extend ActiveSupport::Concern

  # URL components
  def url
    properties[PropertyKeys::URL]
  end

  def host
    properties[PropertyKeys::HOST]
  end

  def path
    properties[PropertyKeys::PATH]
  end

  def query_params
    properties[PropertyKeys::QUERY_PARAMS] || {}
  end

  # Referrer components
  def referrer
    properties[PropertyKeys::REFERRER]
  end

  def referrer_host
    properties[PropertyKeys::REFERRER_HOST]
  end

  def referrer_path
    properties[PropertyKeys::REFERRER_PATH]
  end

  # UTM parameters
  def utm_source
    properties[PropertyKeys::UTM_SOURCE]
  end

  def utm_medium
    properties[PropertyKeys::UTM_MEDIUM]
  end

  def utm_campaign
    properties[PropertyKeys::UTM_CAMPAIGN]
  end

  def utm_content
    properties[PropertyKeys::UTM_CONTENT]
  end

  def utm_term
    properties[PropertyKeys::UTM_TERM]
  end

  # Attribution
  def channel
    properties[PropertyKeys::CHANNEL]
  end
end
