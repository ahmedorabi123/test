class ShipmentEventSerializer
  def self.call(event)
    {
      id: event.id,
      fulfillment_id: event.fulfillment_id,
      kind: event.kind,
      payload: event.payload || {},
      actor_id: event.actor_id,
      actor_name: actor_name(event.actor),
      created_at: event.created_at
    }
  end

  def self.actor_name(actor)
    return nil unless actor

    actor.respond_to?(:display_name) ? actor.display_name : actor.email
  end
end