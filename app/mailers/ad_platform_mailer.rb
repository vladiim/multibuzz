# frozen_string_literal: true

class AdPlatformMailer < ApplicationMailer
  def api_usage_warning(platform_name:, operations_today:, limit:, percentage:)
    @platform_name = platform_name
    @operations_today = operations_today
    @limit = limit
    @percentage = percentage
    @remaining = limit - operations_today

    mail(
      to: FormSubmissionMailer::NOTIFICATION_EMAIL,
      subject: "[mbuzz] #{platform_name} API usage at #{percentage}% (#{number_with_delimiter(operations_today)}/#{number_with_delimiter(limit)})"
    )
  end

  private

  def number_with_delimiter(number)
    ActiveSupport::NumberHelper.number_to_delimited(number)
  end
end
