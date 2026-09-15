class CreateProductChannels < ActiveRecord::Migration[8.1]
  # Which channels a product is offered in. A product with NO rows here is
  # universal (visible in every channel); a product with rows is restricted to
  # exactly those channels — so only the channel-specific SKUs need uploading.
  def change
    create_table :product_channels do |t|
      t.references :product, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.timestamps
    end
    add_index :product_channels, %i[product_id channel_id], unique: true
  end
end
