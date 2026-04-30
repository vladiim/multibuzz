# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Orchestrator. Fetches all pages of /me/adaccounts, parses each, returns a
    # flat list of active accounts.
    #
    # Test posture: VCR cassettes recorded against live Meta API in Sub-phase
    # 2.8 (full OAuth flow). Pure parser logic is fully unit-tested in
    # ListAdAccountsParser.
    class ListAdAccounts
      def initialize(access_token:)
        @access_token = access_token
      end

      def call
        { success: true, accounts: fetch_all_pages }
      rescue StandardError => e
        { success: false, errors: [ e.message ] }
      end

      private

      attr_reader :access_token

      def fetch_all_pages
        accounts = []
        body = client.get(AD_ACCOUNTS_URI, query: { fields: AD_ACCOUNT_FIELDS })

        loop do
          parser = ListAdAccountsParser.new(body: body)
          accounts.concat(parser.accounts)
          next_url = parser.next_page_url
          break unless next_url

          body = client.get(URI(next_url))
        end

        accounts
      end

      def client
        @client ||= ApiClient.new(access_token: access_token)
      end
    end
  end
end
