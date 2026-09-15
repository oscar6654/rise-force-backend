class CreateChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :channels do |t|
      t.string  :code, null: false
      t.string  :name, null: false
      t.text    :description
      t.integer :status, null: false, default: 0

      t.timestamps
    end
    add_index :channels, :code, unique: true
  end
end
