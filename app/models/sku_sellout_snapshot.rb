# Per-seller per-SKU confirmed sellout (pieces) from vcsi_rise, scoped to focus
# SKUs. Fed by Vcsi::FocusSkuSyncJob so focus-SKU incentives run on true data.
class SkuSelloutSnapshot < ApplicationRecord
  belongs_to :seller
  belongs_to :product, optional: true

  def self.pieces_for(seller, product_ids, month: Date.current.beginning_of_month)
    where(seller: seller, product_id: product_ids, period_date: month).sum(:pieces)
  end

  # Focus-SKU incentives key on it_barcode: one barcode may span several
  # item_keys/SKUs, and any of them counts. Sum pieces across the barcodes.
  def self.pieces_for_barcodes(seller, barcodes, month: Date.current.beginning_of_month)
    where(seller: seller, it_barcode: barcodes, period_date: month).sum(:pieces)
  end
end
