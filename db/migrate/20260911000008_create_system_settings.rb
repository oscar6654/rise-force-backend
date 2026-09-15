class CreateSystemSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :system_settings do |t|
      t.string  :key,         null: false
      t.text    :value
      t.string  :value_type,  null: false, default: "string"
      t.string  :category,    null: false, default: "general"
      t.string  :description
      t.boolean :encrypted,   null: false, default: false
      t.boolean :required,    null: false, default: false
      t.string  :test_status, default: "untested"

      t.timestamps
    end

    add_index :system_settings, :key, unique: true
    add_index :system_settings, :category
  end
end
