# frozen_string_literal: true

class Export < ApplicationRecord
  EXPORT_TYPES = DashboardTabs::EXPORTABLE
  EXPIRY_DURATION = 1.hour
  DOWNLOAD_URL_TTL = 5.minutes

  belongs_to :account

  has_one_attached :csv

  has_prefix_id :exp

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :export_type, presence: true, inclusion: { in: EXPORT_TYPES }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def blob_key
    "accounts/#{account.prefix_id}/exports/#{prefix_id}.csv"
  end

  def download_url
    csv.url(
      expires_in: DOWNLOAD_URL_TTL,
      disposition: "attachment",
      filename: ActiveStorage::Filename.new(filename),
      content_type: "text/csv"
    )
  end

  def cleanup!
    csv.purge if csv.attached?
    destroy!
  end
end
