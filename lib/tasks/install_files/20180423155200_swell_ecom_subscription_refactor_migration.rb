class SwellEcomSubscriptionRefactorMigration < ActiveRecord::Migration[5.1]
	def change

		add_column :subscriptions, :type, :string, default: nil
		add_index :subscriptions, [ :type, :id ]

	end
end
