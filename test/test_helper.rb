ENV["RAILS_ENV"] ||= "test"
ENV["BROWSERSLIST_IGNORE_OLD_DATA"] ||= "1"
$VERBOSE = nil # Suppress Ruby warnings during tests
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Clear cache before each test to ensure isolation
    setup { Rails.cache.clear }
  end
end
