module Webhooks
  # Shopify webhook endpoint — public, HMAC-verified.
  # Deduplicates by (source, external_id) = (shopify, X-Shopify-Webhook-Id).
  # Enqueues async processing via ProcessWebhookJob.
  class ShopifyController < ActionController::API
    # Public endpoint — bypass JWT/auth. We verify HMAC manually.
    skip_forgery_protection rescue nil

    def receive
      raw_body  = request.raw_post
      signature = request.headers["X-Shopify-Hmac-Sha256"]
      topic     = request.headers["X-Shopify-Topic"] || params[:topic]
      webhook_id = request.headers["X-Shopify-Webhook-Id"].presence ||
                   "no-id-#{SecureRandom.hex(8)}"

      unless ::Shopify::HmacVerifier.verify(
               raw_body:         raw_body,
               header_signature: signature
             )
        return render json: { error: "invalid_hmac" }, status: :unauthorized
      end

      unless ::Shopify::EventNormalizer.supports?(topic)
        # Acknowledge unknown topics so Shopify doesn't retry forever,
        # but don't persist/process them.
        return render json: { status: "ignored", topic: topic }, status: :ok
      end

      payload = parse_json(raw_body)

      event = WebhookEvent.create!(
        source:      "shopify",
        topic:       topic,
        external_id: webhook_id,
        payload:     payload,
        received_at: Time.current
      )

      Shopify::ProcessWebhookJob.perform_later(event.id)

      render json: { status: "accepted", id: event.id }, status: :accepted
    rescue ActiveRecord::RecordNotUnique
      # Duplicate delivery — Shopify retries; safely ACK.
      render json: { status: "duplicate" }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      # Model-level uniqueness validation caught the duplicate before the DB did.
      if e.record&.errors&.of_kind?(:external_id, :taken)
        render json: { status: "duplicate" }, status: :ok
      else
        render json: { error: "invalid_payload", detail: e.message }, status: :unprocessable_content
      end
    rescue JSON::ParserError
      render json: { error: "invalid_json" }, status: :bad_request
    end

    private

    def parse_json(body)
      body.present? ? JSON.parse(body) : {}
    end
  end
end
