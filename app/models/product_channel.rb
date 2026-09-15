# Maps a product to a channel it is offered in (see CreateProductChannels for
# the universal-vs-restricted rule). Uploaded in bulk keyed by item_key + channel_code.
class ProductChannel < ApplicationRecord
  belongs_to :product
  belongs_to :channel

  validates :product_id, uniqueness: { scope: :channel_id }
end
