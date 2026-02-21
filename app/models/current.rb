# frozen_string_literal: true

# Thread-safe global state using ActiveSupport::CurrentAttributes
#
# Usage in controllers:
#   Current.user = user
#   Current.account = account
#
# Usage anywhere in the request:
#   Current.user
#   Current.account
#
# Automatically reset between requests.
#
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :account

  def user=(user)
    super
    self.account ||= user&.primary_account
  end
end
