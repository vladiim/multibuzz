# frozen_string_literal: true

module AdPlatforms
  # Pulls the connect-time metadata key/value pair out of the form params.
  # The picker submits two key fields (`metadata_key` from the dropdown and
  # `metadata_key_new` from the typed input) and likewise two value fields.
  # Whichever side has a non-empty, non-sentinel value wins.
  #
  # Returns a single-key hash like `{ "location" => "Eumundi-Noosa" }` or `{}`
  # when either side is missing — the AcceptConnectionService and Normalizer
  # handle the empty case downstream.
  class ConnectMetadataExtractor
    NEW_SENTINEL = "__new__"

    def self.call(params)
      key = pick(params[:metadata_key_new], params[:metadata_key])
      value = pick(params[:metadata_value_new], params[:metadata_value])

      return {} if key.blank? || value.blank?

      { key => value }
    end

    def self.pick(new_input, dropdown)
      return new_input if new_input.present?
      return nil if dropdown.blank? || dropdown == NEW_SENTINEL

      dropdown
    end
  end
end
