# Channel availability for products — which channels each SKU is offered in.
# Bulk-managed via the CSV import (Import::ProductChannelsImporter).
class ProductChannelsController < ApplicationController
  before_action -> { authorize!(:product, :view) }, only: [:index]

  def index
    @channels = Channel.order(:name)
    @channel = params[:channel_id].present? ? Channel.find_by(id: params[:channel_id]) : nil

    scope = ProductChannel.includes(:product, :channel).joins(:product)
    scope = scope.where(channel_id: @channel.id) if @channel
    scope = scope.where("products.sku ILIKE :q OR products.description ILIKE :q", q: "%#{ProductChannel.sanitize_sql_like(params[:q])}%") if params[:q].present?
    @mappings = scope.order("products.description").page(params[:page]).per(50)

    @per_channel = ProductChannel.group(:channel_id).count
    @configured_channels = @per_channel.size
    @total_channels = @channels.size
  end
end
