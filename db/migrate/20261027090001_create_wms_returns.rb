class CreateWmsReturns < ActiveRecord::Migration[8.1]
  def change
    create_table :wms_returns do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.references :store, null: true, foreign_key: true
      t.string  :ref, null: false         # return reference (like a PO for returns)
      t.integer :source, default: 0, null: false # upload=0, manual=1
      t.integer :status, default: 0, null: false # open=0, processing=1, closed=2
      t.string  :notes

      t.timestamps
    end
    add_index :wms_returns, %i[warehouse_id ref], unique: true

    create_table :wms_return_lines do |t|
      t.references :wms_return, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.references :storage_location, null: true, foreign_key: true # where it was dropped
      t.string  :it_barcode
      t.decimal :qty, precision: 14, scale: 2, default: "0.0", null: false
      t.integer :uom, default: 1, null: false      # pc=0, case_uom=1
      t.integer :disposition                        # nil=untagged, saleable=0, damaged=1, quarantine=2
      t.integer :status, default: 0, null: false   # pending=0, processed=1
      t.string  :reason

      t.timestamps
    end
  end
end
