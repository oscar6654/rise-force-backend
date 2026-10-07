class AddResetMonthsAndSection < ActiveRecord::Migration[8.1]
  def change
    # How long an assortment's distribution target runs before it resets:
    # 1 = monthly (default), 3 = calendar quarter (JFM/AMJ/JAS/OND),
    # 6 = calendar half (Jan–Jun / Jul–Dec).
    add_column :assortments, :reset_months, :integer, null: false, default: 1

    # Leaderboard grouping: sellers compete within their section.
    add_column :sellers, :section, :string
    add_index :sellers, :section
  end
end
