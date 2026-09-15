class CreateIncentiveSchemes < ActiveRecord::Migration[8.1]
  def change
    create_table :incentive_schemes do |t|
      t.string :name, null: false
      t.integer :scheme_type, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.references :branch, null: true, foreign_key: true # null = all branches
      t.jsonb :config, null: false, default: {}
      t.date :effective_from
      t.date :effective_to
      t.timestamps
    end
  end
end
