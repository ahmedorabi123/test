# Register domain event subscribers here.
# Format:
#   DomainEvents.subscribe("orders.created") { |event| SomeHandler.new.call(event) }
#
# Subscribers will be added as modules are built (Phase 1+).
Rails.application.config.after_initialize do
  # placeholder — subscribers registered per-phase
end
