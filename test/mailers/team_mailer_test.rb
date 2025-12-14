# frozen_string_literal: true

require "test_helper"

class TeamMailerTest < ActionMailer::TestCase
  test "ownership_transferred_to_new_owner sends to new owner" do
    email = TeamMailer.ownership_transferred_to_new_owner(
      account: account,
      new_owner: new_owner,
      previous_owner: previous_owner
    )

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [new_owner.email], email.to
    assert_match /owner/i, email.subject
    assert_match account.name, email.subject
  end

  test "ownership_transferred_to_previous_owner sends to previous owner" do
    email = TeamMailer.ownership_transferred_to_previous_owner(
      account: account,
      new_owner: new_owner,
      previous_owner: previous_owner
    )

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [previous_owner.email], email.to
    assert_match /owner/i, email.subject
    assert_match account.name, email.subject
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def new_owner
    @new_owner ||= users(:three)
  end

  def previous_owner
    @previous_owner ||= users(:one)
  end
end
