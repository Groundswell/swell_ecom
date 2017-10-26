class SwellEcomSubscriptionsMigration < ActiveRecord::Migration
	def change

		create_table :subscription do |t|
			t.references	:user

			t.datetime		:start_at
			t.datetime		:end_at, default: nil

			t.datetime		:current_period_start_at
			t.datetime		:current_period_end_at

			t.integer		:amount
			t.integer		:trial_amount
			t.string 		:currency, default: 'USD'

			t.string		:interval, default: 'month' #day, week, month, year
			t.integer		:interval_value, default: 1

			t.string		:payment_gateway
			t.string		:payment_gateway_subscription_id
			t.string		:payment_gateway_customer_profile_id
			t.string		:payment_gateway_customer_payment_profile_id

			t.timestamps
		end

		create_table :subscription_items do |t|
			t.references	:user
			t.references	:plan
			t.integer		:quantity, default: 1
			t.timestamps
		end

		create_table :plan do |t|

			t.integer 		:price, default: 0 # cents, recurring price
			t.string		:interval, default: 'month' #day, week, month, year
			t.integer		:interval_value, default: 1
			t.integer		:max_intervals, default: nil # for fixed length subscription
			t.string		:statement_descriptor

			t.integer 		:trial_price, default: 0 # cents, recurring price
			t.string		:trial_interval, default: 'month' #day, week, month, year
			t.integer		:trial_interval_value, default: 1
			t.integer		:trial_max_intervals, default: 0
			t.string		:trial_statement_descriptor # a null value default to statement_descriptor

			t.integer		:plan_type, default: 1 # physical, digital

			# copied products:
			t.references 	:category
			t.string 		:title
			t.string		:caption
			t.string 		:slug
			t.string 		:avatar
			# t.integer		:default_product_type, default: 1 # physical, digital
			t.string 		:fulfilled_by, default: 'self' # self, download, amazon, printful
			t.integer		:status, 	default: 0
			t.text 			:description
			t.text 			:content
			t.datetime		:publish_at
			t.datetime		:preorder_at
			t.datetime		:release_at
			# t.integer 		:suggested_price, default: 0
			# t.integer 		:price, default: 0
			t.string 		:currency, default: 'USD'
			t.integer 		:inventory, default: -1
			t.string 		:tags, array: true, default: '{}'
			t.string		:tax_code, default: nil
			t.hstore		:properties, default: {}
			t.timestamps
		end
		add_index :subscriptions, :tags, using: 'gin'
		add_index :subscriptions, :category_id
		add_index :subscriptions, :slug, unique: true
		add_index :subscriptions, :status

	end
end
