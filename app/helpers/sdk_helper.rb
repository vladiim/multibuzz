# frozen_string_literal: true

module SdkHelper
  def live_sdks
    SdkRegistry.live
  end

  def coming_soon_sdks
    SdkRegistry.coming_soon
  end

  def server_side_sdks
    SdkRegistry.server_side
  end

  def platform_sdks
    SdkRegistry.platform
  end

  def sdk_by_key(key)
    SdkRegistry.find(key)
  end

  def sdk_status_badge_class(status)
    case status
    when SdkStatuses::LIVE
      "bg-green-100 text-green-800"
    when SdkStatuses::BETA
      "bg-yellow-100 text-yellow-800"
    when SdkStatuses::COMING_SOON
      "bg-gray-100 text-gray-600"
    end
  end

  def sdk_icon_path(sdk)
    "icons/sdks/#{sdk.icon}.svg"
  end

  def sdk_icon_for(sdk, css_class: "w-10 h-10")
    render partial: "shared/icons/sdks/#{sdk.icon}", locals: { class: css_class }
  end
end
