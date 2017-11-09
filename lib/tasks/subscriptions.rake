# desc "Explaining what the task does"
namespace :swell_ecom do

	task :process_subscriptions do

		@shipping_service = SwellEcom.shipping_service_class.constantize.new( SwellEcom.shipping_service_config )
		@tax_service = SwellEcom.tax_service_class.constantize.new( SwellEcom.tax_service_config )
		@transaction_service = SwellEcom.transaction_service_class.constantize.new( SwellEcom.transaction_service_config )



		SwellEcom::Subscription.active.where( 'next_charged_at < :now', now: Time.now ).find_each do |subscription|

			# create order, process transaction

			plan = subscription.subscription_plan

			order = Order.new(
				billing_address: subscription.billing_address,
				shipping_address: subscription.shipping_address,
			)
			if subscription.trial?
				order.order_items.new item: subscription, price: plan.trial_price, subtotal: plan.trial_price * order_item.quantity, order_item_type: 'prod', quantity: subscription.quantity, title: plan.title, tax_code: plan.tax_code
			else
				order.order_items.new item: subscription, price: plan.price, subtotal: plan.price * order_item.quantity, order_item_type: 'prod', quantity: subscription.quantity, title: plan.title, tax_code: plan.tax_code
			end

			@shipping_service.calculate( order )
			@tax_service.calculate( order )

			if @transaction_service.process( order )
				# @todo send receipt via email
			else
				# mark subscription as failed if the transaction failed
				subscription.failed!
			end




		end

	end

	task :send_subscription_reminders do

		reminder_day = Time.now + 1.week

		# @todo remind subscribers of upcoming renewals

	end

end
