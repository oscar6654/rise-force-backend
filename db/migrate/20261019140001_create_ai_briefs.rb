class CreateAiBriefs < ActiveRecord::Migration[8.1]
  def change
    # Precomputed AI text (seller game plan, manager digest, store pitch…) keyed
    # by owner + kind + day. One row per subject/kind/day; regenerated daily.
    create_table :ai_briefs do |t|
      t.string :kind, null: false                  # seller_plan | manager_digest | store_pitch
      t.references :subject, polymorphic: true, null: false # Seller / Manager / Store
      t.date :period_date, null: false
      t.text :body
      t.string :model
      t.timestamps
    end
    add_index :ai_briefs, [:subject_type, :subject_id, :kind, :period_date],
              unique: true, name: "idx_ai_briefs_subject_kind_date"
  end
end
