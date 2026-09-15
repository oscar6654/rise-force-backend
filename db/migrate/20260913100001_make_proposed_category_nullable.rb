class MakeProposedCategoryNullable < ActiveRecord::Migration[8.1]
  # Sellers now pick the store CHANNEL at enrollment; the backend assigns the
  # default category. A null proposed_category means "no category proposed —
  # apply the configurable enrollment default".
  def up
    change_column_null :store_registrations, :proposed_category, true
    change_column_default :store_registrations, :proposed_category, from: 0, to: nil
  end

  def down
    change_column_default :store_registrations, :proposed_category, from: nil, to: 0
    change_column_null :store_registrations, :proposed_category, false, 0
  end
end
