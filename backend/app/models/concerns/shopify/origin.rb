module Shopify
  module Origin
    extend ActiveSupport::Concern

    READ_ONLY_MESSAGE = "This record is managed by Shopify and cannot be modified in the ERP.".freeze
    SKIP_THREAD_KEY = :shopify_origin_skip_read_only

    included do
      class_attribute :shopify_origin_id_column, instance_accessor: false, default: nil
      class_attribute :shopify_read_only_except, instance_accessor: false, default: []

      validate :prevent_shopify_origin_update, on: :update
      before_destroy :prevent_shopify_origin_destroy
    end

    class << self
      def without_read_only
        previous = Thread.current[SKIP_THREAD_KEY]
        Thread.current[SKIP_THREAD_KEY] = true
        yield
      ensure
        Thread.current[SKIP_THREAD_KEY] = previous
      end

      def skip_read_only?
        Thread.current[SKIP_THREAD_KEY] == true
      end
    end

    class_methods do
      def shopify_origin_via(column_name, read_only_except: [])
        self.shopify_origin_id_column = column_name.to_s
        self.shopify_read_only_except = Array(read_only_except).map(&:to_s)

        scope :shopify_origin, -> { where.not(column_name => nil) }
        scope :manual_origin, -> { where(column_name => nil) }
      end
    end

    def shopify_origin?
      origin_column = self.class.shopify_origin_id_column
      return true if origin_column.present? && public_send(origin_column).present?
      return true if respond_to?(:source) && source.to_s == "shopify"

      shopify_mapping_origin?
    end
    alias shopify_linked? shopify_origin?

    def ensure_mutable_locally!
      return true unless shopify_origin?

      raise ActiveRecord::ReadOnlyRecord, READ_ONLY_MESSAGE
    end

    private

    def prevent_shopify_origin_update
      return if Shopify::Origin.skip_read_only?
      return unless persisted? && shopify_origin?

      blocked_attributes = changes_to_save.keys - allowed_shopify_origin_changes
      errors.add(:base, READ_ONLY_MESSAGE) if blocked_attributes.any?
    end

    def prevent_shopify_origin_destroy
      return if Shopify::Origin.skip_read_only?
      return unless shopify_origin?

      errors.add(:base, READ_ONLY_MESSAGE)
      throw(:abort)
    end

    def allowed_shopify_origin_changes
      self.class.shopify_read_only_except + %w[updated_at]
    end

    def shopify_mapping_origin?
      return false unless persisted? && defined?(ShopifyMapping)

      ShopifyMapping.exists?(local_type: self.class.name, local_id: id)
    end
  end
end