class AddDiscountRateToStores < ActiveRecord::Migration[8.1]
  def change
    # Per-customer exclusive discount, applied EX-VAT at the end of the order
    # (catalog prices are VAT-inclusive). Stored as a rate: 0.025 = 2.5%.
    add_column :stores, :discount_rate, :decimal, precision: 7, scale: 4, default: 0, null: false
  end
end
