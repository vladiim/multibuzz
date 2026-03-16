# frozen_string_literal: true

class AdPlatformMailer < ApplicationMailer
  def api_usage_warning(operations_today:, limit:, percentage:)
    @operations_today = operations_today
    @limit = limit
    @percentage = percentage
    @remaining = limit - operations_today

    mail(
      to: FormSubmissionMailer::NOTIFICATION_EMAIL,
      subject: "[mbuzz] Google Ads API usage at #{percentage}% (#{number_with_delimiter(operations_today)}/#{number_with_delimiter(limit)})"
    )
  end

  private

  def number_with_delimiter(number)
    ActiveSupport::NumberHelper.number_to_delimited(number)
  end
end
