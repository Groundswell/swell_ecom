module SwellEcom
	class OrderItem < ActiveRecord::Base
		self.table_name = 'order_items'

		belongs_to :item, polymorphic: true
		belongs_to :order

		enum order_item_type: { 'sku' => 1, 'tax' => 2, 'shipping' => 3, 'discount' => 4 }

	end
end
