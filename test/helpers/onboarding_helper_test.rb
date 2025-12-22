require "test_helper"

class OnboardingHelperTest < ActionView::TestCase
  test "syntax_language_for returns ruby for ruby SDK" do
    assert_equal "ruby", syntax_language_for(ruby_sdk)
  end

  test "syntax_language_for returns python for python SDK" do
    assert_equal "python", syntax_language_for(python_sdk)
  end

  test "syntax_language_for returns javascript for nodejs SDK" do
    assert_equal "javascript", syntax_language_for(nodejs_sdk)
  end

  test "syntax_language_for returns php for php SDK" do
    assert_equal "php", syntax_language_for(php_sdk)
  end

  test "syntax_language_for returns javascript for shopify SDK" do
    assert_equal "javascript", syntax_language_for(shopify_sdk)
  end

  test "syntax_language_for returns bash for rest_api SDK" do
    assert_equal "bash", syntax_language_for(rest_api_sdk)
  end

  test "syntax_language_for returns ruby as default for nil" do
    assert_equal "ruby", syntax_language_for(nil)
  end

  test "syntax_language_for returns ruby for unknown SDK" do
    unknown = SdkRegistry::Sdk.new(
      key: "unknown", name: "Unknown", display_name: "Unknown",
      icon: nil, package_name: nil, package_manager: nil,
      package_url: nil, github_url: nil, docs_url: nil,
      status: "live", released_at: nil, category: "server_side",
      sort_order: 99, install_command: nil, init_code: nil,
      event_code: nil, conversion_code: nil, identify_code: nil,
      middleware_code: nil, verification_command: nil
    )

    assert_equal "ruby", syntax_language_for(unknown)
  end

  private

  def ruby_sdk
    @ruby_sdk ||= SdkRegistry.find("ruby")
  end

  def python_sdk
    @python_sdk ||= SdkRegistry.find("python")
  end

  def nodejs_sdk
    @nodejs_sdk ||= SdkRegistry.find("nodejs")
  end

  def php_sdk
    @php_sdk ||= SdkRegistry.find("php")
  end

  def shopify_sdk
    @shopify_sdk ||= SdkRegistry.find("shopify")
  end

  def rest_api_sdk
    @rest_api_sdk ||= SdkRegistry.find("rest_api")
  end
end
