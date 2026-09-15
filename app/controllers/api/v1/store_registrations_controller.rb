module Api
  module V1
    class StoreRegistrationsController < BaseController
      # POST /api/v1/store_registrations (multipart)
      # { client_uuid, name, owner_name, address, latitude, longitude,
      #   channel_id, contact_number, storefront_photo? }
      # The seller picks the CHANNEL; the backend assigns the default enrollment
      # category so the store can sell immediately (a reviewer reassigns it later).
      # `proposed_category` is still accepted for legacy clients but optional.
      # Returns a provisional store so the app can order immediately.
      def create
        uuid = params.require(:client_uuid)
        reg = StoreRegistration.find_by(client_uuid: uuid)
        unless reg
          reg = StoreRegistration.create!(
            client_uuid: uuid, seller: current_seller, branch: current_seller.branch,
            channel_id: params[:channel_id], name: params.require(:name),
            owner_name: params[:owner_name], contact_number: params[:contact_number],
            address: params[:address], latitude: params[:latitude], longitude: params[:longitude],
            proposed_category: params[:proposed_category].presence
          )
          reg.storefront_photo.attach(params[:storefront_photo]) if params[:storefront_photo]
          reg.provision_store!
          StoreDuplicateDetector.new(reg).detect!
        end
        render json: { data: registration_json(reg), meta: meta }, status: :created
      end

      # GET /api/v1/store_registrations?updated_since=  (status updates for the app)
      def index
        rows = since_scope(StoreRegistration.where(seller: current_seller)).map { |r| registration_json(r) }
        render json: { data: rows, meta: meta }
      end

      private

      def registration_json(reg)
        store = reg.provisional_store || reg.created_store
        { registration_id: reg.id, status: reg.status, duplicate_flags: reg.duplicate_flags,
          provisional_store: (store && { id: store.id, code: store.code,
            provisional_code: store.provisional_code, store_code: store.store_code,
            channel_id: store.channel_id, category: store.category, status: store.status }) }
      end
    end
  end
end
