# frozen_string_literal: true

module AdPlatforms
  # Pure normalizer for ad-platform connection metadata.
  #
  # Keys are lowercased + stripped so they line up with SDK convention
  # (`properties: { location: ... }`). Values keep their case so user-typed
  # distinctions like "Premium Brand" vs "premium brand" survive. Blank pairs
  # are dropped so partially-filled forms produce an empty hash, not invalid
  # rows.
  class MetadataNormalizer
    def self.call(input)
      return {} unless input.is_a?(Hash)

      input.each_with_object({}) do |(raw_key, raw_value), out|
        key = normalize_key(raw_key)
        value = raw_value.to_s.strip
        next if key.empty? || value.empty?

        out[key] = value
      end
    end

    # Lowercase + strip a single key, so dimension keys and metadata keys
    # normalise identically. Reused by CustomDimension.
    def self.normalize_key(raw_key)
      raw_key.to_s.downcase.strip
    end
  end
end
