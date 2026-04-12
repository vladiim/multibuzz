# frozen_string_literal: true

class ApplicationService
  def call
    run
  rescue ActiveRecord::RecordInvalid => e
    report_error(e)
    error_result([ "Record invalid: #{e.message}" ])
  rescue ActiveRecord::RecordNotFound => e
    report_error(e)
    error_result([ "Record not found: #{e.message}" ])
  rescue StandardError => e
    report_error(e)
    error_result([ "Something went wrong. Please try again shortly." ])
  end

  private

  def run
    raise NotImplementedError, "Subclasses must implement #run"
  end

  def success_result(data = {})
    { success: true }.merge(data)
  end

  def error_result(errors)
    { success: false, errors: Array(errors) }
  end

  def report_error(exception)
    Rails.error.report(exception, handled: true, context: error_context)
  end

  def error_context
    ctx = { service: self.class.name }
    ctx[:account_id] = @account.id if defined?(@account) && @account.respond_to?(:id)
    ctx
  end
end
