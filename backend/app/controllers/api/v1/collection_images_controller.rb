module Api
  module V1
    class CollectionImagesController < ApplicationController
      ALLOWED_TYPES = Api::V1::ProductImagesController::ALLOWED_TYPES
      MAX_SIZE_BYTES = Api::V1::ProductImagesController::MAX_SIZE_BYTES

      before_action :set_collection
      before_action :ensure_collection_mutable

      def create
        authorize @collection, :update?
        file = params[:file]
        return render_error(422, "no_file", "Please attach a file under 'file'") unless file
        return render_error(422, "unsupported_type", "Unsupported file type: #{file.content_type}") unless ALLOWED_TYPES.include?(file.content_type)
        return render_error(422, "file_too_large", "File #{file.original_filename} exceeds #{MAX_SIZE_BYTES / 1.megabyte} MB") if file.size > MAX_SIZE_BYTES

        @collection.uploaded_image.purge if @collection.uploaded_image.attached?
        @collection.uploaded_image.attach(
          io: file.to_io,
          filename: file.original_filename,
          content_type: file.content_type
        )

        render json: { data: attachment_payload(@collection.uploaded_image.attachment) }, status: :created
      rescue ActiveStorage::IntegrityError => e
        render_error(422, "integrity_error", e.message)
      end

      def destroy
        authorize @collection, :update?
        @collection.uploaded_image.purge_later if @collection.uploaded_image.attached?
        head :no_content
      end

      private

      def set_collection
        @collection = Collection.find(params[:collection_id])
      end

      def ensure_collection_mutable
        ensure_not_shopify_origin!(@collection)
      end

      def attachment_payload(attachment)
        {
          id: attachment.id,
          filename: attachment.filename.to_s,
          content_type: attachment.content_type,
          byte_size: attachment.byte_size,
          url: Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
        }
      end
    end
  end
end
