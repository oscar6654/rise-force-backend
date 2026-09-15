class CreateJobLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :job_logs do |t|
      t.integer :job_type, null: false                  # store_import/product_import/pricing_publish/*_sync/order_export...
      t.integer :status, null: false, default: 0        # pending/running/completed/failed/partial
      t.references :triggered_by, foreign_key: { to_table: :users }, null: true
      t.string  :filename
      t.integer :total_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.integer :skipped_rows, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.jsonb   :result_summary, null: false, default: {}
      t.jsonb   :rejected_records_data, null: false, default: []
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :job_logs, [:job_type, :status]
    add_index :job_logs, :created_at
  end
end
