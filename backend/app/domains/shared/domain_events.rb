# DomainEvents — thin in-process event bus wrapping ActiveSupport::Notifications.
#
# Usage:
#   DomainEvents.publish("orders.created", OrderCreatedEvent.new(...))
#   DomainEvents.subscribe("orders.created") { |event| ... }
#
# Subscribers are registered in config/initializers/domain_events.rb.
module DomainEvents
  NAMESPACE = "erp.domain"

  def self.publish(event_type, payload)
    ActiveSupport::Notifications.instrument("#{NAMESPACE}.#{event_type}", payload: payload)
  end

  def self.subscribe(event_type, &block)
    ActiveSupport::Notifications.subscribe("#{NAMESPACE}.#{event_type}") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      block.call(event.payload[:payload])
    end
  end
end
