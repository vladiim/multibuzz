# frozen_string_literal: true

module GuidedSetup::Milestones
  extend ActiveSupport::Concern

  MILESTONES = %w[
    kickoff_call install_completed integration_connected training_call value_check
  ].freeze

  # integration_target maps to an AdPlatformConnection#platform. Lets the
  # admin milestone "Integration connected" derive automatically from real
  # connection data instead of being clicked manually. sgtm/none don't
  # have a connection model -- the admin can still manually stamp those.
  AD_PLATFORM_FOR_INTEGRATION_TARGET = {
    "meta" => "meta_ads",
    "google_ads" => "google_ads"
  }.freeze

  def integration_connected_at
    super || derived_integration_connected_at
  end

  def mark_in_progress!
    update!(status: :in_progress, accepted_at: Time.current)
  end

  def record_milestone!(milestone)
    name = milestone.to_s
    raise ArgumentError, "unknown milestone: #{name}" unless MILESTONES.include?(name)

    update!(milestone_attributes(name))
  end

  def cancel!
    update!(status: :cancelled)
  end

  private

  def derived_integration_connected_at
    platform = AD_PLATFORM_FOR_INTEGRATION_TARGET[integration_target]
    return nil unless platform

    account.ad_platform_connections.where(platform: platform).order(:created_at).first&.created_at
  end

  def milestone_attributes(name)
    { "#{name}_at" => Time.current }.tap do |attrs|
      attrs.merge!(status: :delivered, completed_at: Time.current) if name == "value_check"
    end
  end
end
