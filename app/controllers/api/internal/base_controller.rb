# frozen_string_literal: true

module Api
  module Internal
    # Base controller for anonymous internal endpoints called by browser
    # JavaScript on the marketing site (currently: consent banner). No
    # API key authentication, no account scoping. Sensitive routes opt
    # out of marketing analytics by default since the entire namespace
    # handles state changes from anonymous visitors.
    class BaseController < ActionController::API
      include ConsentHelper

      private

      def real_client_ip
        request.headers["CF-Connecting-IP"].presence || request.remote_ip
      end
    end
  end
end
