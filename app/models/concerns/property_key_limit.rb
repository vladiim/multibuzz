# frozen_string_literal: true

module PropertyKeyLimit
  extend ActiveSupport::Concern

  MAX_PROPERTY_KEYS = 25

  class_methods do
    def validates_property_key_count(field, reserved: [])
      reserved_keys = reserved.map(&:to_s).freeze

      validate(lambda do
        hash = public_send(field)
        next unless hash.is_a?(Hash)
        custom_count = hash.keys.map(&:to_s).reject { |k| reserved_keys.include?(k) }.size
        next if custom_count <= MAX_PROPERTY_KEYS

        errors.add(field, "cannot have more than #{MAX_PROPERTY_KEYS} custom keys (got #{custom_count})")
      end)
    end
  end
end
