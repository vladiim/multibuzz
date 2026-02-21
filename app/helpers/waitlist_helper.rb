# frozen_string_literal: true

module WaitlistHelper
  def waitlist_button(feature_key:, feature_name:, context: nil, label: "Join Waitlist", **options, &block)
    css_class = options.delete(:class) || ""
    content = block_given? ? capture(&block) : label

    logged_in? ? auto_submit_button(feature_key, feature_name, context, css_class, content) : modal_trigger_button(feature_key, feature_name, css_class, content)
  end

  def waitlist_modal(feature_key:, feature_name:, context: nil)
    render partial: "shared/waitlist_modal",
      locals: { feature_key: feature_key, feature_name: feature_name, context: context }
  end

  private

  def auto_submit_button(feature_key, feature_name, context, css_class, content)
    button_to feature_waitlist_path,
      params: { feature_key: feature_key, feature_name: feature_name, context: context }.compact,
      method: :post,
      class: css_class do
        content
      end
  end

  def modal_trigger_button(feature_key, _feature_name, css_class, content)
    content_tag :button,
      type: "button",
      class: css_class,
      data: {
        controller: "modal",
        action: "click->modal#open",
        modal_target_value: "waitlist-modal-#{feature_key}"
      } do
        content
      end
  end
end
