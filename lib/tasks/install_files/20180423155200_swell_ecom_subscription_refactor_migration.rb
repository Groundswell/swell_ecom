class SwellEcomSubscriptionRefactorMigration < ActiveRecord::Migration[5.1]
	def change

		add_column :subscriptions, :type, :string, default: SwellEcom.default_subscription_class
		add_index :subscriptions, [ :type, :id ]

	end
end
