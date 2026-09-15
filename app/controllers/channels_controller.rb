class ChannelsController < ApplicationController
  before_action -> { authorize!(:channel, :view) }, only: [:index, :show]
  before_action -> { authorize!(:channel, :create) }, only: [:new, :create]
  before_action -> { authorize!(:channel, :update) }, only: [:edit, :update]
  before_action :set_channel, only: [:show, :edit, :update]

  def index
    @channels = Channel.order(:code)
  end

  def show; end

  def new
    @channel = Channel.new
  end

  def create
    @channel = Channel.new(channel_params)
    if @channel.save
      redirect_to channels_path, notice: "Channel created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @channel.update(channel_params)
      redirect_to channels_path, notice: "Channel updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_channel
    @channel = Channel.find(params[:id])
  end

  def channel_params
    params.require(:channel).permit(:code, :name, :description, :status)
  end
end
