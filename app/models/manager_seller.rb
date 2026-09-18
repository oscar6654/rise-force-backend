class ManagerSeller < ApplicationRecord
  belongs_to :manager
  belongs_to :seller

  validates :seller_id, uniqueness: { scope: :manager_id }
end
