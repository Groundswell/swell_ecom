class SwellEcomOrderStatusMigration < ActiveRecord::Migration
	def change

		add_column :orders, :payment_status, :integer, default: 0
		add_column :orders, :fulfillment_status, :integer, default: 0

	end
end
