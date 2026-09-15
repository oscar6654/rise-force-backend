class CreatePlanograms < ActiveRecord::Migration[8.1]
  def change
    create_table :planograms do |t|
      t.references :channel, foreign_key: true, null: false
      t.string  :title, null: false
      t.integer :status, null: false, default: 0      # draft/active/archived
      t.date    :effective_date
      t.references :uploaded_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end
    add_index :planograms, [:channel_id, :status]
  end
end
