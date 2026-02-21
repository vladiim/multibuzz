# frozen_string_literal: true

require "test_helper"

class Visitors::IdentificationServiceTest < ActiveSupport::TestCase
  test "extracts visitor_id from cookie when present" do
    result = service_with_cookie("existing_visitor_abc123").call

    assert_equal "existing_visitor_abc123", result[:visitor_id]
  end

  test "generates new visitor_id when cookie missing" do
    result = service_without_cookie.call

    assert_predicate result[:visitor_id], :present?
    assert_equal 64, result[:visitor_id].length
    assert_match(/\A[a-f0-9]+\z/, result[:visitor_id])
  end

  test "generates different visitor_ids for different requests without cookies" do
    result1 = service_without_cookie.call
    result2 = Visitors::IdentificationService.new(MockRequest.new({}), account).call

    refute_equal result1[:visitor_id], result2[:visitor_id]
  end

  test "returns set_cookie header" do
    result = service_without_cookie.call

    assert_predicate result[:set_cookie], :present?
    assert_includes result[:set_cookie], "_mbuzz_vid="
  end

  test "set_cookie includes correct cookie name and value" do
    result = service_with_cookie("test_visitor_id").call

    assert_includes result[:set_cookie], "_mbuzz_vid=test_visitor_id"
  end

  test "set_cookie includes expiry of 1 year" do
    result = service_without_cookie.call

    assert_includes result[:set_cookie], "Expires="
    expiry_match = result[:set_cookie].match(/Expires=([^;]+)/)

    assert expiry_match
    expiry_time = Time.httpdate(expiry_match[1])

    assert_in_delta 1.year.from_now, expiry_time, 1.minute
  end

  test "set_cookie includes HttpOnly flag" do
    result = service_without_cookie.call

    assert_includes result[:set_cookie], "HttpOnly"
  end

  test "set_cookie includes SameSite=Lax" do
    result = service_without_cookie.call

    assert_includes result[:set_cookie], "SameSite=Lax"
  end

  test "set_cookie includes Path=/" do
    result = service_without_cookie.call

    assert_includes result[:set_cookie], "Path=/"
  end

  test "set_cookie includes Secure flag in production" do
    original_env = Rails.env
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new("production"))

    result = Visitors::IdentificationService.new(MockRequest.new({}), account).call

    assert_includes result[:set_cookie], "Secure"
  ensure
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new(original_env))
  end

  test "set_cookie excludes Secure flag in test environment" do
    result = service_without_cookie.call

    refute_includes result[:set_cookie], "Secure;"
  end

  test "preserves existing visitor_id from cookie in set_cookie header" do
    result = service_with_cookie("preserve_this_visitor").call

    assert_equal "preserve_this_visitor", result[:visitor_id]
    assert_includes result[:set_cookie], "_mbuzz_vid=preserve_this_visitor"
  end

  test "returns consistent visitor_id and set_cookie value" do
    result = service_without_cookie.call

    assert_includes result[:set_cookie], "_mbuzz_vid=#{result[:visitor_id]}"
  end

  private

  class MockRequest
    attr_reader :cookies

    def initialize(cookies)
      @cookies = cookies
    end
  end

  def service_with_cookie(visitor_id)
    Visitors::IdentificationService.new(MockRequest.new({ "_mbuzz_vid" => visitor_id }), account)
  end

  def service_without_cookie
    @service_without_cookie ||= Visitors::IdentificationService.new(MockRequest.new({}), account)
  end

  def account
    @account ||= accounts(:one)
  end
end
