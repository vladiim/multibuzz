# frozen_string_literal: true

class Plan < ApplicationRecord
  has_many :accounts

  scope :active, -> { where(is_active: true) }
  scope :sorted, -> { order(:sort_order) }
  scope :paid, -> { where.not(slug: ::Billing::PLAN_FREE) }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :events_included, presence: true, numericality: { greater_than: 0 }

  def free?
    slug == ::Billing::PLAN_FREE
  end

  def has_overage?
    overage_price_cents.present?
  end

  def monthly_price
    monthly_price_cents.to_f / ::Billing::CENTS_PER_DOLLAR
  end

  def overage_price_per_10k
    return nil unless overage_price_cents

    overage_price_cents.to_f / ::Billing::CENTS_PER_DOLLAR
  end

  def formatted_price
    return ::Billing::FREE_PRICE_LABEL if free?

    format(::Billing::PRICE_FORMAT, monthly_price.to_i)
  end

  def formatted_events
    if events_included >= ::Billing::EVENTS_PER_MILLION
      format(::Billing::EVENTS_MILLIONS_FORMAT, events_included / ::Billing::EVENTS_PER_MILLION)
    else
      format(::Billing::EVENTS_THOUSANDS_FORMAT, events_included / ::Billing::EVENTS_PER_THOUSAND)
    end
  end
end
