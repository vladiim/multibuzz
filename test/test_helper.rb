ENV["RAILS_ENV"] ||= "test"
ENV["BROWSERSLIST_IGNORE_OLD_DATA"] ||= "1"
$VERBOSE = nil # Suppress Ruby warnings during tests

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    minimum_coverage 90
    enable_coverage :branch

    add_group "Models", "app/models"
    add_group "Controllers", "app/controllers"
    add_group "Services", "app/services"
    add_group "Constants", "app/constants"
    add_group "Jobs", "app/jobs"

    add_filter "/test/"
    add_filter "/db/"
    add_filter "/config/"
  end
end

require_relative "../config/environment"
require "rails/test_help"
require "prosopite"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    parallelize_setup do |worker|
      SimpleCov.command_name "minitest-#{worker}" if ENV["COVERAGE"]
    end

    parallelize_teardown do |_worker|
      SimpleCov.result if ENV["COVERAGE"]
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Clear cache before each test to ensure isolation
    setup do
      Rails.cache.clear
      Prosopite.scan
    end

    teardown do
      Prosopite.finish
    end
  end
end
