module Admin
  class DataIntegrityController < BaseController
    def index
      @accounts = Account.active.order(:name).map { |a| account_health(a) }
    end

    def show
      @account = Account.find(params[:id])
      @latest_checks = @account.data_integrity_checks
        .where("created_at > ?", 7.days.ago)
        .order(created_at: :desc)
      @current_checks = latest_per_check
    end

    private

    def account_health(account)
      latest = account.data_integrity_checks
        .where("created_at >= ?", 24.hours.ago)
        .worst_first
        .first
      {
        account: account,
        status: latest&.status || "unknown",
        worst_check: latest&.check_name || "—",
        worst_value: latest&.value,
        last_run: latest&.created_at
      }
    end

    def latest_per_check
      @account.data_integrity_checks
        .where(id: @account.data_integrity_checks
          .select("DISTINCT ON (check_name) id")
          .order(:check_name, created_at: :desc))
        .order(Arel.sql("CASE status WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END"))
    end
  end
end
