# frozen_string_literal: true

require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  test "rejects traits exceeding 50KB" do
    identity.traits = { "data" => "x" * 51_200 }

    assert_not identity.valid?
    assert identity.errors[:traits].any? { |e| e.include?("exceeds maximum size") }
  end

  test "accepts traits within 50KB" do
    identity.traits = { "email" => "user@example.com", "name" => "Test User" }

    assert_predicate identity, :valid?
  end

  test "model does not reject traits with more than 25 keys (services truncate)" do
    identity.traits = (1..30).each_with_object({}) { |i, h| h["trait#{i}"] = i }

    assert_predicate identity, :valid?
  end

  private

  def identity
    @identity ||= identities(:one)
  end
end
