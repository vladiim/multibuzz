# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Pure parser. Takes a Meta /me/adaccounts response body, returns the active
    # accounts and the next-page URL if present. Filters disabled / closed
    # accounts so they don't show up in the connect picker.
    class ListAdAccountsParser
      def initialize(body:)
        @body = body || {}
      end

      def accounts
        active_rows.map { |row| build_account(row) }
      end

      def next_page_url
        body.dig(FIELD_PAGING, FIELD_NEXT)
      end

      private

      attr_reader :body

      def active_rows
        Array(body[FIELD_DATA]).select { |row| row[FIELD_ACCOUNT_STATUS] == AD_ACCOUNT_STATUS_ACTIVE }
      end

      def build_account(row)
        {
          id: row[FIELD_ID],
          name: row[FIELD_NAME],
          currency: row[FIELD_CURRENCY],
          timezone_name: row[FIELD_TIMEZONE_NAME]
        }
      end
    end
  end
end
