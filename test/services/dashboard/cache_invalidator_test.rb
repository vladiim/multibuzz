# frozen_string_literal: true

require "test_helper"

class Dashboard::CacheInvalidatorTest < ActiveSupport::TestCase
  setup do
    Dashboard::CacheInvalidator.reset_delete_matched_support!
    Rails.cache.clear
  end

  teardown do
    if @original_cache
      Rails.cache = @original_cache
      @original_cache = nil
    end
    Dashboard::CacheInvalidator.reset_delete_matched_support!
  end

  test "deletes matching cache entries for each section when backend supports delete_matched" do
    Rails.cache.write(key_for("conversions", "foo"), "stale")
    Rails.cache.write(key_for("funnel", "bar"), "stale")
    Rails.cache.write("unrelated/key", "kept")

    invalidator.call

    assert_nil Rails.cache.read(key_for("conversions", "foo"))
    assert_nil Rails.cache.read(key_for("funnel", "bar"))
    assert_equal "kept", Rails.cache.read("unrelated/key")
  end

  test "does not raise when backend does not support delete_matched" do
    swap_cache_to_unsupported

    assert_nothing_raised { invalidator.call }
  end

  test "probes backend support exactly once across many calls" do
    swap_cache_to_unsupported

    3.times { invalidator.call }

    assert_equal 1, unsupported_store.delete_matched_call_count
  end

  test "delete_matched_supported? is true under the test cache backend" do
    assert_predicate Dashboard::CacheInvalidator, :delete_matched_supported?
  end

  test "delete_matched_supported? is false under a backend that raises NotImplementedError" do
    swap_cache_to_unsupported

    refute_predicate Dashboard::CacheInvalidator, :delete_matched_supported?
  end

  private

  def invalidator = @invalidator ||= Dashboard::CacheInvalidator.new(account)
  def account = @account ||= accounts(:one)
  def key_for(section, suffix) = "dashboard/#{section}/#{account.prefix_id}/#{suffix}"

  def swap_cache_to_unsupported
    @original_cache = Rails.cache
    Rails.cache = unsupported_store
    Dashboard::CacheInvalidator.reset_delete_matched_support!
  end

  def unsupported_store = @unsupported_store ||= UnsupportedStore.new

  class UnsupportedStore
    attr_reader :delete_matched_call_count

    def initialize
      @delete_matched_call_count = 0
    end

    def delete_matched(_pattern, _options = nil)
      @delete_matched_call_count += 1
      raise NotImplementedError
    end
  end
end
