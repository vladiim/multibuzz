# frozen_string_literal: true

require "sinatra/base"
require "json"
require "mbuzz"

# Initialize Mbuzz with environment variables
Mbuzz.init(
  api_key: ENV.fetch("MBUZZ_API_KEY"),
  api_url: ENV.fetch("MBUZZ_API_URL", "http://localhost:3000/api/v1"),
  debug: ENV.fetch("MBUZZ_DEBUG", "false") == "true"
)

class MbuzzRubyTestapp < Sinatra::Base
  set :views, File.join(__dir__, "views")

  # Main page with test forms
  get "/" do
    erb :index
  end

  # Return current IDs as JSON
  get "/api/ids" do
    content_type :json
    {
      visitor_id: current_visitor_id,
      session_id: current_session_id,
      user_id: Mbuzz.user_id
    }.to_json
  end

  # Trigger an event - use Client.track directly with explicit IDs from cookies
  post "/api/event" do
    content_type :json
    data = JSON.parse(request.body.read)

    result = Mbuzz::Client.track(
      visitor_id: current_visitor_id,
      session_id: current_session_id,
      event_type: data["event_type"],
      properties: symbolize_keys(data["properties"] || {})
    )

    {
      success: result != false,
      result: result
    }.to_json
  end

  # Trigger identify - use Client.identify directly with explicit visitor_id
  post "/api/identify" do
    content_type :json
    data = JSON.parse(request.body.read)

    result = Mbuzz::Client.identify(
      user_id: data["user_id"],
      visitor_id: current_visitor_id,
      traits: data["traits"] || {}
    )

    {
      success: result != false,
      result: result
    }.to_json
  end

  # Trigger conversion - use Client.conversion directly with explicit IDs
  post "/api/conversion" do
    content_type :json
    data = JSON.parse(request.body.read)

    result = Mbuzz::Client.conversion(
      visitor_id: current_visitor_id,
      user_id: data["user_id"],
      conversion_type: data["conversion_type"],
      revenue: data["revenue"],
      is_acquisition: data["is_acquisition"] || false,
      inherit_acquisition: data["inherit_acquisition"] || false,
      properties: symbolize_keys(data["properties"] || {})
    )

    {
      success: result != false,
      result: result
    }.to_json
  end

  # -------------------------------------------------------------------
  # Background job simulation endpoints (no request context)
  # These test Mbuzz.event/conversion called outside middleware scope
  # -------------------------------------------------------------------

  # BROKEN PATTERN: No visitor_id passed - should fail after SDK fix
  post "/api/background_event_no_visitor" do
    content_type :json
    data = JSON.parse(request.body.read)

    result = Mbuzz.event(
      data["event_type"],
      **symbolize_keys(data["properties"] || {})
    )

    { success: result != false, result: result }.to_json
  end

  # CORRECT PATTERN: Explicit visitor_id passed - should always work
  post "/api/background_event_with_visitor" do
    content_type :json
    data = JSON.parse(request.body.read)

    result = Mbuzz.event(
      data["event_type"],
      visitor_id: data["visitor_id"],
      **symbolize_keys(data["properties"] || {})
    )

    { success: result != false, result: result }.to_json
  end

  # BROKEN PATTERN: No visitor_id for conversion - should fail
  post "/api/background_conversion_no_visitor" do
    content_type :json
    data = JSON.parse(request.body.read)

    result = Mbuzz.conversion(
      data["conversion_type"],
      revenue: data["revenue"],
      **symbolize_keys(data["properties"] || {})
    )

    { success: result != false, result: result }.to_json
  end

  # CORRECT PATTERN: Explicit visitor_id for conversion - should work
  post "/api/background_conversion_with_visitor" do
    content_type :json
    data = JSON.parse(request.body.read)

    result = Mbuzz.conversion(
      data["conversion_type"],
      visitor_id: data["visitor_id"],
      revenue: data["revenue"],
      **symbolize_keys(data["properties"] || {})
    )

    { success: result != false, result: result }.to_json
  end

  private

  # Read visitor_id from the cookie set by middleware
  def current_visitor_id
    request.cookies[Mbuzz::VISITOR_COOKIE_NAME]
  end

  # Session ID is now server-side (v0.7.0+), no cookie
  def current_session_id
    nil
  end

  def symbolize_keys(hash)
    hash.transform_keys(&:to_sym)
  end
end
