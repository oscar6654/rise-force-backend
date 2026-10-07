class CreateDisplayTargets < ActiveRecord::Migration[8.1]
  def change
    # A campaign = one uploaded xlsx "base" file of display/visibility targets,
    # scoped to a from/to window the operator sets at upload time.
    create_table :display_campaigns do |t|
      t.string  :name, null: false
      t.date    :period_from, null: false
      t.date    :period_to, null: false
      t.string  :source_filename
      t.integer :status, null: false, default: 0 # active / archived
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    # Target lines parsed from the xlsx (the "must execute" list). store_code is
    # the CU_#### extracted from col A; store_id is resolved against the master.
    create_table :display_targets do |t|
      t.references :display_campaign, null: false, foreign_key: true, index: true
      t.references :store, foreign_key: true # nullable: CU code may be outside our master
      t.string :store_code, null: false
      t.string :promotion_name, null: false
      t.string :category
      t.string :brand # blank = matches any brand in the category
      t.timestamps
    end
    add_index :display_targets, [:display_campaign_id, :store_code]

    # Execution evidence parsed from the CSV result file. A new CSV upload
    # supersedes the previous one (same campaign) — tracked by batch_token.
    create_table :display_evidences do |t|
      t.references :display_campaign, null: false, foreign_key: true, index: true
      t.references :store, foreign_key: true
      t.string :store_code, null: false
      t.string :promotion_name, null: false
      t.date   :from_date
      t.date   :to_date
      t.string :category
      t.string :brand
      t.text   :image_url
      t.date   :photo_taken_at
      t.string :activity_type
      t.string :batch_token
      t.timestamps
    end
    add_index :display_evidences, [:display_campaign_id, :store_code, :promotion_name],
              name: "idx_display_evidence_match"
  end
end
