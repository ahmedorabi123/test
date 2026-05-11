module Api
  module V1
    # Multipart upload + delete endpoints for product images backed by
    # ActiveStorage. The existing url-based ProductImage records are unaffected.
    class ProductImagesController < ApplicationController
      ALLOWED_TYPES = %w[image/png image/jpeg image/jpg image/webp image/gif].freeze
      MAX_SIZE_BYTES = 5.megabytes

      before_action :set_product

      # POST /api/v1/products/:product_id/images
      # Accepts one or more files under params[:files] or params[:file].
      def create
        authorize @product, :update?

        files = Array(params[:files]).compact
        files = [ params[:file] ] if files.empty? && params[:file].present?
        return render_error(422, "no_file", "Please attach at least one file under 'files' or 'file'") if files.empty?

        attached = files.map do |file|
          unless ALLOWED_TYPES.include?(file.content_type)
            return render_error(422, "unsupported_type", "Unsupported file type: #{file.content_type}")
          end
          if file.size > MAX_SIZE_BYTES
            return render_error(422, "file_too_large", "File #{file.original_filename} exceeds #{MAX_SIZE_BYTES / 1.megabyte} MB")
          end

          blob = ActiveStorage::Blob.create_and_upload!(
            io: file.to_io,
            filename: file.original_filename,
            content_type: file.content_type
          )
          @product.uploaded_images_attachments.create!(blob: blob)
        end

        render json: { data: attached.map { |i| attachment_payload(i) } }, status: :created
      rescue ActiveStorage::IntegrityError => e
        render_error(422, "integrity_error", e.message)
      end

      # DELETE /api/v1/products/:product_id/images/:id
      # :id is the ActiveStorage::Attachment id.
      def destroy
        authorize @product, :update?
        attachment = @product.uploaded_images_attachments.find(params[:id])
        attachment.purge_later
        head :no_content
      end

      private

      def set_product
        @product = Product.find(params[:product_id])
      end

      def attachment_payload(attachment)
        {
          id:           attachment.id,
          filename:     attachment.filename.to_s,
          content_type: attachment.content_type,
          byte_size:    attachment.byte_size,
          url:          Rails.application.routes.url_helpers.rails_blob_url(attachment, host: request.base_url)
        }
      end
    end
  end
end
