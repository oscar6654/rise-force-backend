class StockSnapshot < ApplicationRecord
  belongs_to :store
  belongs_to :product
end
