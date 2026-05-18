# frozen_string_literal: true

require "test_helper"

class AdminToolsTest < ActiveSupport::TestCase
  test "every ALL entry has every required field populated" do
    missing = AdminTools::ALL.flat_map { |tool| missing_fields(tool).map { |f| "#{tool.name || '(unnamed)'}.#{f}" } }

    assert_empty missing, "tools with missing fields: #{missing.join(', ')}"
  end

  test "grouped returns category => tools hash" do
    grouped = AdminTools.grouped

    assert_kind_of Hash, grouped
    assert grouped.keys.all?(String), "category keys should be strings"
    assert grouped.values.all? { |tools| tools.all? { |t| t.is_a?(AdminTools::Tool) } }
  end

  test "every registered path resolves to a real route" do
    AdminTools::ALL.each do |tool|
      Rails.application.routes.recognize_path(tool.path, method: :get)
    rescue ActionController::RoutingError => e
      flunk "path #{tool.path} (#{tool.name}) did not resolve: #{e.message}"
    end
  end

  test "paths are unique" do
    paths = AdminTools::ALL.map(&:path)

    assert_equal paths.uniq, paths, "duplicate paths in AdminTools::ALL"
  end

  private

  REQUIRED_FIELDS = %i[category name path description].freeze

  def missing_fields(tool)
    REQUIRED_FIELDS.reject { |field| tool.public_send(field).present? }
  end
end
