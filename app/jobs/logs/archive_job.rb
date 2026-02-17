# frozen_string_literal: true

module Logs
  class ArchiveJob < ApplicationJob
    def perform
      ArchiveService.new.call
    end
  end
end
