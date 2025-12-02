# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# --- Plans ---
puts "Seeding plans..."

plans = [
  {
    name: "Free",
    slug: Billing::PLAN_FREE,
    monthly_price_cents: Billing::FREE_MONTHLY_PRICE_CENTS,
    events_included: Billing::FREE_EVENT_LIMIT,
    overage_price_cents: nil,
    sort_order: Billing::FREE_SORT_ORDER
  },
  {
    name: "Starter",
    slug: Billing::PLAN_STARTER,
    monthly_price_cents: Billing::STARTER_MONTHLY_PRICE_CENTS,
    events_included: Billing::STARTER_EVENT_LIMIT,
    overage_price_cents: Billing::STARTER_OVERAGE_CENTS,
    sort_order: Billing::STARTER_SORT_ORDER
  },
  {
    name: "Growth",
    slug: Billing::PLAN_GROWTH,
    monthly_price_cents: Billing::GROWTH_MONTHLY_PRICE_CENTS,
    events_included: Billing::GROWTH_EVENT_LIMIT,
    overage_price_cents: Billing::GROWTH_OVERAGE_CENTS,
    sort_order: Billing::GROWTH_SORT_ORDER
  },
  {
    name: "Pro",
    slug: Billing::PLAN_PRO,
    monthly_price_cents: Billing::PRO_MONTHLY_PRICE_CENTS,
    events_included: Billing::PRO_EVENT_LIMIT,
    overage_price_cents: Billing::PRO_OVERAGE_CENTS,
    sort_order: Billing::PRO_SORT_ORDER
  }
]

plans.each do |plan_attrs|
  Plan.find_or_create_by!(slug: plan_attrs[:slug]) do |plan|
    plan.name = plan_attrs[:name]
    plan.monthly_price_cents = plan_attrs[:monthly_price_cents]
    plan.events_included = plan_attrs[:events_included]
    plan.overage_price_cents = plan_attrs[:overage_price_cents]
    plan.sort_order = plan_attrs[:sort_order]
  end
end

puts "Created #{Plan.count} plans"
