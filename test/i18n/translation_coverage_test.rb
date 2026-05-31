# frozen_string_literal: true

require "test_helper"

# Guards against the "Translation missing" class of bug, where a controller or
# view references a translation key that does not exist in config/locales.
#
# Rails' lazy lookup (`t(".success")`) silently returns a "Translation missing"
# string instead of raising, so request/controller tests that only assert
# `flash[:notice]` is present pass even while the page is visibly broken. This
# test statically resolves every lookup against the loaded locale and fails the
# build if any key is missing.
class TranslationCoverageTest < ActiveSupport::TestCase
  # `t("a.b.c")` / `t('.lazy')` — captures the dotted key, requires the string
  # to be a pure key literal (interpolated keys like `t("a.#{x}")` won't match).
  LOOKUP = /\bt\(\s*["']([a-zA-Z0-9_.]+)["']/

  CONTROLLERS = Dir.glob(Rails.root.join("app/controllers/**/*.rb"))
    .reject { |f| f.include?("/concerns/") } # concern lookups resolve via the including controller's action
  VIEWS = Dir.glob(Rails.root.join("app/views/**/*.erb"))

  test "every lazy controller translation lookup resolves to a real key" do
    missing = CONTROLLERS.flat_map { |file| unresolved_controller_lookups(file) }

    assert_empty missing, <<~MSG
      #{missing.size} controller translation lookup(s) resolve to a missing key:

      #{missing.map { |m| "  #{m[:file]}\n    t(\".#{m[:suffix]}\")  — expected under: #{m[:namespace]}.<action>.#{m[:suffix]}" }.join("\n")}
    MSG
  end

  test "every lazy view translation lookup resolves to a real key" do
    missing = VIEWS.flat_map { |file| unresolved_view_lookups(file) }

    assert_empty missing, <<~MSG
      #{missing.size} view translation lookup(s) resolve to a missing key:

      #{missing.map { |m| "  #{m[:file]}\n    t(\".#{m[:suffix]}\")  — expected: #{m[:full_key]}" }.join("\n")}
    MSG
  end

  test "every absolute translation key referenced in app code resolves" do
    files = CONTROLLERS + VIEWS + Dir.glob(Rails.root.join("app/helpers/**/*.rb"))
    missing = files.flat_map { |file| unresolved_absolute_lookups(file) }

    assert_empty missing, <<~MSG
      #{missing.size} absolute translation key(s) not found in any loaded locale:

      #{missing.map { |m| "  #{m[:file]}\n    t(\"#{m[:key]}\")" }.join("\n")}
    MSG
  end

  private

  # Lazy lookups in a controller resolve to `<controller_path>.<action_name>.<suffix>`
  # at runtime. The suffix may be referenced from a private helper, so we accept
  # the lookup if it resolves under the controller namespace directly or under
  # any method defined in the file (a superset of the real actions).
  def unresolved_controller_lookups(file)
    src = File.read(file)
    namespace = controller_namespace(file)
    candidates = [nil] + src.scan(/^\s*def ([a-z_][a-zA-Z0-9_]*)/).flatten

    lazy_suffixes(src).reject do |suffix|
      candidates.any? { |action| key_exists?([namespace, action, suffix].compact.join(".")) }
    end.map { |suffix| { file: relative(file), suffix:, namespace: } }
  end

  # Lazy lookups in a view resolve to `<view_path>.<template>.<suffix>` exactly.
  def unresolved_view_lookups(file)
    base = view_namespace(file)

    lazy_suffixes(File.read(file)).reject { |suffix| key_exists?("#{base}.#{suffix}") }
      .map { |suffix| { file: relative(file), suffix:, full_key: "#{base}.#{suffix}" } }
  end

  def unresolved_absolute_lookups(file)
    File.read(file).scan(LOOKUP).flatten.uniq
      .reject { |key| key.start_with?(".") }
      .reject { |key| key_exists?(key) }
      .map { |key| { file: relative(file), key: } }
  end

  def lazy_suffixes(src)
    src.scan(LOOKUP).flatten.select { |k| k.start_with?(".") }.map { |k| k.delete_prefix(".") }.uniq
  end

  def controller_namespace(file)
    relative(file).delete_prefix("app/controllers/").delete_suffix("_controller.rb").tr("/", ".")
  end

  def view_namespace(file)
    rel = relative(file).delete_prefix("app/views/")
    dir = File.dirname(rel)
    template = File.basename(rel).split(".").first.delete_prefix("_")
    "#{dir.tr('/', '.')}.#{template}"
  end

  def key_exists?(key)
    I18n.exists?(key, :en)
  end

  def relative(file)
    Pathname.new(file).relative_path_from(Rails.root).to_s
  end
end
