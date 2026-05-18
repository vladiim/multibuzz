# frozen_string_literal: true

# Registry of admin tools surfaced on /admin. Each entry renders as a card
# on Admin::DashboardController#index. Adding a new admin surface means
# appending one entry here — no controller or view changes.
#
# Mirrors SdkRegistry / AdPlatforms::Registry: explicit list of Data.define
# structs over auto-discovery from routes.rb, so descriptions stay
# intentional and non-admin-tool routes (engine sub-paths, etc.) don't
# leak in.
module AdminTools
  Tool = Data.define(:category, :name, :path, :description)

  module Categories
    CUSTOMER_SUPPORT     = "Customer support"
    PLATFORM_OPERATIONS  = "Platform operations"
    DIAGNOSTICS          = "Diagnostics"
  end

  ALL = [
    Tool.new(
      category: Categories::CUSTOMER_SUPPORT,
      name: "Submissions",
      path: "/admin/submissions",
      description: "Inbound form submissions across accounts"
    ),
    Tool.new(
      category: Categories::CUSTOMER_SUPPORT,
      name: "Billing",
      path: "/admin/billing",
      description: "Billing summary and usage across accounts"
    ),
    Tool.new(
      category: Categories::PLATFORM_OPERATIONS,
      name: "Feature Flags",
      path: "/admin/feature_flags",
      description: "Toggle features per account"
    ),
    Tool.new(
      category: Categories::PLATFORM_OPERATIONS,
      name: "Conversion Dispatches",
      path: "/admin/conversion_dispatches",
      description: "Outbound conversion-feedback sends to Meta CAPI and Google EC"
    ),
    Tool.new(
      category: Categories::DIAGNOSTICS,
      name: "Customer Metrics",
      path: "/admin/customer_metrics",
      description: "Aggregate platform usage and trends"
    ),
    Tool.new(
      category: Categories::DIAGNOSTICS,
      name: "Data Integrity",
      path: "/admin/data_integrity",
      description: "Data integrity checks across accounts"
    ),
    Tool.new(
      category: Categories::DIAGNOSTICS,
      name: "Errors",
      path: "/admin/errors",
      description: "Recent server errors (SolidErrors)"
    )
  ].freeze

  def self.grouped
    ALL.group_by(&:category)
  end
end
