class CreateOrderBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :order_batches do |t|
      t.references :branch, foreign_key: true, null: false
      t.references :seller, foreign_key: true, null: true
      t.string   :batch_number, null: false
      t.integer  :sequence, null: false
      t.integer  :status, null: false, default: 0   # open/locked/downloaded/invoiced/voided
      t.integer  :order_count, null: false, default: 0
      t.decimal  :total_amount, precision: 14, scale: 2, null: false, default: 0
      t.datetime :locked_at
      t.references :locked_by, foreign_key: { to_table: :users }, null: true
      t.datetime :downloaded_at
      t.references :downloaded_by, foreign_key: { to_table: :users }, null: true
      t.string   :download_file_ref
      t.datetime :invoiced_at

      t.timestamps
    end
    add_index :order_batches, :batch_number, unique: true
    add_index :order_batches, [:branch_id, :seller_id, :sequence], unique: true
    add_index :order_batches, [:branch_id, :seller_id, :status]
    # At most one OPEN batch per (branch, seller) — deterministic "next batch".
    add_index :order_batches, [:branch_id, :seller_id],
              unique: true, where: "status = 0", name: "index_one_open_batch_per_branch_seller"
  end
end
