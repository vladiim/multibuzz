class SdkRegistry
  SDK_DATA = YAML.load_file(Rails.root.join("config/sdk_registry.yml")).freeze

  Sdk = Data.define(
    :key, :name, :display_name, :icon, :package_name, :package_manager,
    :package_url, :github_url, :docs_url, :status, :released_at, :category,
    :sort_order, :install_command, :init_code, :event_code, :conversion_code,
    :identify_code, :middleware_code, :verification_command
  ) do
    def live?
      status == SdkStatuses::LIVE
    end

    def beta?
      status == SdkStatuses::BETA
    end

    def coming_soon?
      status == SdkStatuses::COMING_SOON
    end

    def server_side?
      category == SdkCategories::SERVER_SIDE
    end

    def platform?
      category == SdkCategories::PLATFORM
    end

    def api?
      category == SdkCategories::API
    end

    def status_badge
      SdkStatuses::BADGES[status]
    end
  end

  class << self
    def all
      @all ||= SDK_DATA.map { |key, data| build_sdk(key, data) }
        .sort_by(&:sort_order)
    end

    def find(key)
      all.find { |sdk| sdk.key == key.to_s }
    end

    def live
      all.select(&:live?)
    end

    def coming_soon
      all.select(&:coming_soon?)
    end

    def server_side
      all.select(&:server_side?)
    end

    def platform
      all.select(&:platform?)
    end

    def api
      all.select(&:api?)
    end

    def for_onboarding
      all
    end

    def for_homepage
      all
    end

    private

    def build_sdk(key, data)
      Sdk.new(
        key: key,
        name: data["name"],
        display_name: data["display_name"],
        icon: data["icon"],
        package_name: data["package_name"],
        package_manager: data["package_manager"],
        package_url: data["package_url"],
        github_url: data["github_url"],
        docs_url: data["docs_url"],
        status: data["status"],
        released_at: data["released_at"],
        category: data["category"],
        sort_order: data["sort_order"],
        install_command: data["install_command"],
        init_code: data["init_code"]&.strip,
        event_code: data["event_code"]&.strip,
        conversion_code: data["conversion_code"]&.strip,
        identify_code: data["identify_code"]&.strip,
        middleware_code: data["middleware_code"]&.strip,
        verification_command: data["verification_command"]
      )
    end
  end
end
