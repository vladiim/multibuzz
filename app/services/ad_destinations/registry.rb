# frozen_string_literal: true

# Maps a `ConversionDestination#platform` string to its dispatcher
# class. Mirror of `AdPlatforms::Registry` (inbound spend pull).
#
# Adding a new outbound platform: add an entry to DISPATCHERS mapping
# the platform name to the orchestrator class. The destination model's
# PLATFORMS list is the source of truth for valid strings.
module AdDestinations
  class Registry
    DISPATCHERS = {
      meta_capi: AdDestinations::Meta::Dispatcher
    }.freeze

    def self.dispatcher_for(destination)
      dispatcher_class = DISPATCHERS.fetch(destination.platform.to_sym) do
        raise ArgumentError, "No dispatcher for platform: #{destination.platform}"
      end

      ->(conversion) { dispatcher_class.new(conversion: conversion, destination: destination).dispatch! }
    end
  end
end
