module TeamHelper
  ROLE_BADGES = {
    "owner" => { bg: "bg-purple-100", text: "text-purple-800", label: "Owner" },
    "admin" => { bg: "bg-blue-100", text: "text-blue-800", label: "Admin" },
    "member" => { bg: "bg-gray-100", text: "text-gray-800", label: "Member" },
    "viewer" => { bg: "bg-gray-100", text: "text-gray-600", label: "Viewer" }
  }.freeze

  STATUS_BADGES = {
    "accepted" => { bg: "bg-green-100", text: "text-green-800", label: "Active" },
    "pending" => { bg: "bg-yellow-100", text: "text-yellow-800", label: "Pending" },
    "declined" => { bg: "bg-gray-100", text: "text-gray-600", label: "Declined" },
    "revoked" => { bg: "bg-red-100", text: "text-red-800", label: "Revoked" }
  }.freeze

  def render_role_badge(role)
    badge = ROLE_BADGES.fetch(role.to_s, ROLE_BADGES["member"])
    content_tag(:span, badge[:label],
      class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge[:bg]} #{badge[:text]}")
  end

  def render_status_badge(status)
    badge = STATUS_BADGES.fetch(status.to_s, STATUS_BADGES["pending"])
    content_tag(:span, badge[:label],
      class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge[:bg]} #{badge[:text]}")
  end
end
