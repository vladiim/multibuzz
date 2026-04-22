# frozen_string_literal: true

module Conversions
  class BatchReattributionJob < ApplicationJob
    queue_as :default

    def perform(conversion_ids)
      Conversion.where(id: conversion_ids).find_each do |conversion|
        ReattributionService.new(conversion).call
      end
    end
  end
end
