# frozen_string_literal: true

# Suppress duplicate solid_errors emails: only send if no other occurrence
# of the same error has been recorded in the dedup window.
Rails.application.config.to_prepare do
  SolidErrors::Occurrence.class_eval <<~RUBY, __FILE__, __LINE__ + 1
    EMAIL_DEDUP_WINDOW = 24.hours unless const_defined?(:EMAIL_DEDUP_WINDOW)

    private

    def send_email
      return if duplicate_within_window?

      SolidErrors::ErrorMailer.error_occurred(self).deliver_later
    end

    def duplicate_within_window?
      self.class
        .where(error_id: error_id)
        .where.not(id: id)
        .where(created_at: EMAIL_DEDUP_WINDOW.ago..)
        .exists?
    end
  RUBY
end
