# A configurable earning rule for sellers. Payouts are computed on vcsi_rise
# CONFIRMED sales (the true source), so a seller's earnings settle as invoices
# land — see IncentiveCalculator. config (jsonb) holds per-type parameters:
#
#  target_multiplier: { base_payout, tiers: [{ pct: 100, payout: 2000 },
#                                            { pct: 120, payout: 2000, multiplier: 1.5 }] }
#  focus_sku:         { product_ids: [..], rate_per_piece: 0.50 }  # per PIECE
#  assortment_completion: { assortment_type: "focus", payout_per_store: 50 }
#  coverage:          { metric: "productive_call_pct"|"active_stores",
#                       threshold: 80, payout: 1500, per_unit: 100 }
class IncentiveScheme < ApplicationRecord
  belongs_to :branch, optional: true # null = all branches

  enum :scheme_type, { target_multiplier: 0, focus_sku: 1, assortment_completion: 2, coverage: 3 }
  enum :status, { active: 0, inactive: 1 }, default: :active

  scope :live_on, ->(date) {
    where(status: :active)
      .where("effective_from IS NULL OR effective_from <= ?", date)
      .where("effective_to IS NULL OR effective_to >= ?", date)
  }

  # Schemes that apply to a seller (their branch or all-branch).
  scope :for_seller, ->(seller) { where(branch_id: [nil, seller.branch_id]) }

  def cfg = (config || {}).with_indifferent_access
end
