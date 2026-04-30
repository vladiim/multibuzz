# frozen_string_literal: true

module Account::FeatureFlags
  extend ActiveSupport::Concern

  included do
    has_many :feature_flags, class_name: "AccountFeatureFlag", dependent: :destroy
  end

  def feature_enabled?(name)
    enabled_feature_names.include?(name.to_s)
  end

  def enable_feature!(name)
    feature_flags.find_or_create_by!(flag_name: name.to_s)
    @enabled_feature_names = nil
  end

  def disable_feature!(name)
    feature_flags.where(flag_name: name.to_s).delete_all
    @enabled_feature_names = nil
  end

  private

  def enabled_feature_names
    @enabled_feature_names ||= feature_flags.pluck(:flag_name).to_set
  end
end
