require "test_helper"

module DataIntegrity
  class AccountHealthServiceTest < ActiveSupport::TestCase
    setup do
      account.data_integrity_checks.destroy_all
    end

    test "returns critical when any check is critical" do
      create_check(status: "healthy", check_name: "ghost_session_rate")
      create_check(status: "critical", check_name: "session_inflation")

      assert_equal "critical", service.call
    end

    test "returns warning when worst check is warning" do
      create_check(status: "healthy", check_name: "ghost_session_rate")
      create_check(status: "warning", check_name: "session_inflation")

      assert_equal "warning", service.call
    end

    test "returns healthy when all checks are healthy" do
      create_check(status: "healthy", check_name: "ghost_session_rate")
      create_check(status: "healthy", check_name: "session_inflation")

      assert_equal "healthy", service.call
    end

    test "returns unknown when no checks exist" do
      assert_equal "unknown", service.call
    end

    test "ignores checks older than 2 hours" do
      create_check(status: "critical", check_name: "ghost_session_rate", created_at: 3.hours.ago)

      assert_equal "unknown", service.call
    end

    private

    def account = @account ||= accounts(:one)
    def service = DataIntegrity::AccountHealthService.new(account)

    def create_check(status:, check_name:, created_at: Time.current)
      account.data_integrity_checks.create!(
        check_name: check_name,
        status: status,
        value: 50.0,
        warning_threshold: 20.0,
        critical_threshold: 50.0,
        created_at: created_at
      )
    end
  end
end
