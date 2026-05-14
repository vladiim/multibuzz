# frozen_string_literal: true

module OnboardingHelper
  SYNTAX_LANGUAGES = {
    "ruby" => "ruby",
    "python" => "python",
    "nodejs" => "javascript",
    "php" => "php",
    "rest_api" => "bash"
  }.freeze

  def syntax_language_for(sdk)
    return "ruby" unless sdk

    SYNTAX_LANGUAGES.fetch(sdk.key, "ruby")
  end
end
