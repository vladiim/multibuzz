# frozen_string_literal: true

# Wire-format constants per ad-platform vendor.
#
# Distinct from `AdPlatforms::*` (inbound services: OAuth + spend pull)
# and `AdDestinations::*` (outbound services: conversion dispatch). This
# namespace holds payload field names, action_source values, API host +
# version strings, and any other vendor-defined wire constants.
module Platforms
end
