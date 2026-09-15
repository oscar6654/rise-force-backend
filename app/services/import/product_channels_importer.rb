module Import
  # Upserts product↔channel availability. CSV headers:
  #   item_key, channel_code [, available]
  # item_key must exist in the product master and channel_code in the channel
  # master (rows referencing unknown keys are rejected). Each row ensures the
  # mapping exists; available = false/0/no/remove deletes it (for corrections).
  class ProductChannelsImporter < BaseImporter
    JOB_TYPE = :product_channel_import

    private

    def import_row(row)
      key  = (row["item_key"] || row["itemkey"] || row["sku"]).to_s.strip
      code = (row["channel_code"] || row["channel"]).to_s.strip
      raise "item_key is required" if key.blank?
      raise "channel_code is required" if code.blank?

      product = Product.find_by("LOWER(sku) = ?", key.downcase)
      raise "unknown item_key '#{key}' — not in product master" if product.nil?

      channel = Channel.find_by("LOWER(code) = ?", code.downcase)
      raise "unknown channel_code '#{code}' — not in channel master" if channel.nil?

      if remove?(row)
        ProductChannel.where(product: product, channel: channel).delete_all
      else
        ProductChannel.find_or_create_by!(product: product, channel: channel)
      end
    end

    def remove?(row)
      row["available"].to_s.strip.downcase.in?(%w[false 0 no remove delete])
    end
  end
end
