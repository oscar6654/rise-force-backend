class CreateReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :receipts do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.string  :po_ref, null: false            # expected-receipt / ASN reference
      t.integer :source, default: 0, null: false # upload=0
      t.integer :status, default: 0, null: false # open=0, receiving=1, received=2, closed=3
      t.string  :import_batch_uuid
      t.text    :notes

      t.timestamps
    end
    add_index :receipts, %i[warehouse_id po_ref], unique: true

    create_table :receipt_lines do |t|
      t.references :receipt, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: true # resolved from it_barcode
      t.string  :it_barcode
      t.decimal :expected_qty, precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :received_qty, precision: 14, scale: 2, default: "0.0", null: false
      t.integer :uom, default: 1, null: false    # pc=0, case_uom=1
      t.integer :status, default: 0, null: false # pending=0, partial=1, received=2, over=3, short=4

      t.timestamps
    end
  end
end
