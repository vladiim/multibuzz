require "test_helper"

class AttributionModelTest < ActiveSupport::TestCase
  test "should belong to account" do
    assert_respond_to model, :account
    assert_equal accounts(:one), model.account
  end

  test "should have many attribution credits" do
    assert_respond_to model, :attribution_credits
  end

  test "should have prefixed id" do
    assert model.prefix_id.start_with?("attr_")
  end

  test "should require name" do
    model.name = nil
    assert_not model.valid?
    assert_includes model.errors[:name], "can't be blank"
  end

  test "should require unique name per account" do
    duplicate = AttributionModel.new(
      account: accounts(:one),
      name: "First Touch",
      model_type: :preset,
      algorithm: :first_touch
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "should allow same name for different accounts" do
    model_account_two = AttributionModel.new(
      account: accounts(:two),
      name: "First Touch",
      model_type: :preset,
      algorithm: :first_touch
    )

    assert model_account_two.valid?
  end

  test "should have preset model_type enum" do
    assert_respond_to model, :preset?
    assert_respond_to model, :custom?

    assert model.preset?
    assert_not model.custom?
  end

  test "should have algorithm enum for preset models" do
    assert_respond_to model, :first_touch?
    assert_respond_to model, :last_touch?
    assert_respond_to model, :linear?
    assert_respond_to model, :time_decay?
    assert_respond_to model, :u_shaped?
    assert_respond_to model, :w_shaped?
    assert_respond_to model, :participation?

    assert model.first_touch?
  end

  test "should scope active models" do
    assert_includes AttributionModel.active, model

    model.update!(is_active: false)
    assert_not_includes AttributionModel.active, model
  end

  test "should scope default model" do
    default = AttributionModel.default_for_account(accounts(:one))
    assert_equal model, default
    assert default.is_default?
  end

  test "should only allow one default per account" do
    model.update!(is_default: false)

    last_touch_model.update!(is_default: true)
    model.reload

    assert_not model.is_default?
    assert last_touch_model.is_default?
  end

  private

  def model
    @model ||= attribution_models(:first_touch)
  end

  def last_touch_model
    @last_touch_model ||= attribution_models(:last_touch)
  end
end
