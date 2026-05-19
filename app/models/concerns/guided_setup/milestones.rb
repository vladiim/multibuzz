# frozen_string_literal: true

module GuidedSetup::Milestones
  extend ActiveSupport::Concern

  MILESTONES = %w[
    kickoff_call install_completed integration_connected training_call value_check
  ].freeze

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

  def milestone_attributes(name)
    { "#{name}_at" => Time.current }.tap do |attrs|
      attrs.merge!(status: :delivered, completed_at: Time.current) if name == "value_check"
    end
  end
end
