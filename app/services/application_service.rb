class ApplicationService
  def call
    run
  rescue ActiveRecord::RecordInvalid => e
    error_result(["Record invalid: #{e.message}"])
  rescue ActiveRecord::RecordNotFound => e
    error_result(["Record not found: #{e.message}"])
  rescue StandardError => e
    error_result(["Internal error: #{e.message}"])
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
end
