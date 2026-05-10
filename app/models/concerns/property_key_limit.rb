# frozen_string_literal: true

# Property keys on ingested JSONB blobs are capped per call. Beyond the cap, we
# keep the first MAX_PROPERTY_KEYS custom keys (insertion order) and silently
# drop the rest. The ingestion service surfaces a warning to the API caller
# so SDK authors can fix instrumentation, but the request still succeeds.
#
# Reserved keys (system-captured fields like url / referrer on conversions)
# do not count toward the cap and are always preserved.
module PropertyKeyLimit
  MAX_PROPERTY_KEYS = 25

  module_function

  def truncate(hash, reserved: [])
    return hash unless hash.is_a?(Hash)

    reserved_keys = reserved.map(&:to_s)
    reserved_part, custom_part = hash.partition { |k, _| reserved_keys.include?(k.to_s) }
    reserved_part.to_h.merge(custom_part.first(MAX_PROPERTY_KEYS).to_h)
  end

  def overflow(hash, reserved: [])
    return 0 unless hash.is_a?(Hash)

    reserved_keys = reserved.map(&:to_s)
    custom_count = hash.keys.count { |k| !reserved_keys.include?(k.to_s) }
    [ custom_count - MAX_PROPERTY_KEYS, 0 ].max
  end

  def truncated?(hash, reserved: [])
    overflow(hash, reserved: reserved).positive?
  end

  def warning_for(field, hash, reserved: [])
    return nil unless hash.is_a?(Hash)

    reserved_keys = reserved.map(&:to_s)
    custom_count = hash.keys.count { |k| !reserved_keys.include?(k.to_s) }
    return nil if custom_count <= MAX_PROPERTY_KEYS

    "#{field}: kept first #{MAX_PROPERTY_KEYS} of #{custom_count} keys, dropped the rest"
  end
end
