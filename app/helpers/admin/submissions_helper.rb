# frozen_string_literal: true

module Admin::SubmissionsHelper
  TYPE_BADGES = {
    "ContactSubmission" => { class: "bg-blue-100 text-blue-800", label: "Contact" },
    "WaitlistSubmission" => { class: "bg-purple-100 text-purple-800", label: "Waitlist" },
    "SdkWaitlistSubmission" => { class: "bg-green-100 text-green-800", label: "SDK" },
    "FeatureWaitlistSubmission" => { class: "bg-amber-100 text-amber-800", label: "Feature" }
  }.freeze

  STATUS_BADGES = {
    "pending" => "bg-gray-100 text-gray-800",
    "contacted" => "bg-blue-100 text-blue-800",
    "completed" => "bg-green-100 text-green-800",
    "spam" => "bg-red-100 text-red-800"
  }.freeze

  def submission_type_badge(submission)
    config = TYPE_BADGES[submission.class.name] || { class: "bg-gray-100 text-gray-800", label: "Unknown" }

    content_tag :span,
      config[:label],
      class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{config[:class]}",
      data: { testid: "type-badge" }
  end

  def submission_status_badge(status)
    badge_class = STATUS_BADGES[status.to_s] || STATUS_BADGES["pending"]

    content_tag :span,
      status.to_s.humanize,
      class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}"
  end

  def submission_type_label(submission)
    TYPE_BADGES[submission.class.name]&.fetch(:label, "Unknown") || "Unknown"
  end

  def submission_details_preview(submission)
    case submission
    when ContactSubmission
      "#{submission.subject}: #{submission.message&.truncate(50)}"
    when WaitlistSubmission
      "#{submission.role} - #{submission.framework}"
    when SdkWaitlistSubmission
      submission.sdk_name
    when FeatureWaitlistSubmission
      submission.feature_name
    else
      "-"
    end
  end
end
