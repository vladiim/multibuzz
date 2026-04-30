# frozen_string_literal: true

require "test_helper"
require "net/http"

class VcrSetupTest < ActiveSupport::TestCase
  test "VCR blocks unrecorded HTTP calls outside a cassette" do
    assert_raises(VCR::Errors::UnhandledHTTPRequestError) do
      Net::HTTP.get(URI("https://example.com/zen"))
    end
  end

  test "VCR replays a hand-crafted cassette" do
    VCR.use_cassette("smoke_replay") do
      response = Net::HTTP.get_response(URI("https://example.com/smoke"))

      assert_equal "200", response.code
      assert_equal "ok", response.body
    end
  end
end
