class AddShowroomFieldsToWarehouses < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      change_table :warehouses, bulk: true do |t|
        t.string  :partner_email
        t.string  :partner_phone
        t.decimal :commission_rate, precision: 5, scale: 4   # 0..1
        t.string  :currency, limit: 3
        t.text    :notes
      end
    end
  end
end
