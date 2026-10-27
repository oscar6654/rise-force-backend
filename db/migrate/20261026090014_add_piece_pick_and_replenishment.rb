class AddPiecePickAndReplenishment < ActiveRecord::Migration[8.1]
  def change
    # The zone that is the loose / broken-case (piece) pick area. Locations in it
    # are piece-pick; everything else is full-case pick. Blank = no split (current
    # behaviour: pick from any pickable bin).
    add_column :warehouses, :piece_pick_zone, :string

    # Each demand/pick line is either a full-CASE pick or a LOOSE (piece) pick.
    add_column :fulfillment_lines, :pack, :integer, default: 0, null: false # case=0, loose=1
    add_column :pick_allocations,  :pack, :integer, default: 0, null: false

    # Replenishment: break N cases from a case bin into the piece zone.
    create_table :replenishment_tasks do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :piece_location, null: true, foreign_key: { to_table: :storage_locations }
      t.references :fulfillment_order, null: true, foreign_key: true # the loose demand that triggered it
      t.references :assigned_to, null: true, foreign_key: { to_table: :warehouse_staffs }
      t.integer :qty_cases, null: false, default: 0
      t.decimal :pieces, precision: 14, scale: 2, null: false, default: "0.0"
      t.integer :trigger, default: 0, null: false # auto=0, manual=1
      t.integer :status, default: 0, null: false  # pending=0, assigned=1, done=2, cancelled=3
      t.datetime :done_at
      t.string :notes

      t.timestamps
    end
    add_index :replenishment_tasks, %i[warehouse_id status]
  end
end
