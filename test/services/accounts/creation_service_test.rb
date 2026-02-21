# frozen_string_literal: true

require "test_helper"

class Accounts::CreationServiceTest < ActiveSupport::TestCase
  test "creates account with valid name" do
    result = service("Acme Corp").call

    assert result[:success]
    assert_equal "Acme Corp", result[:account].name
    assert_equal "acme-corp", result[:account].slug
  end

  test "creates owner membership for user" do
    result = service("My Company").call

    assert result[:success]
    membership = result[:account].account_memberships.first

    assert_equal user, membership.user
    assert_predicate membership, :owner?
    assert_predicate membership, :accepted?
  end

  test "generates unique slug when duplicate exists" do
    Account.create!(name: "Test", slug: "test")

    result = service("Test").call

    assert result[:success]
    assert_match(/^test-\w+$/, result[:account].slug)
  end

  test "returns error for blank name" do
    result = service("").call

    assert_not result[:success]
    assert_includes result[:errors], "Name can't be blank"
  end

  test "creates default attribution models" do
    result = service("New Account").call

    assert result[:success]
    assert_operator result[:account].attribution_models.count, :>, 0
  end

  private

  def service(name)
    Accounts::CreationService.new(user: user, name: name)
  end

  def user
    @user ||= users(:one)
  end
end
