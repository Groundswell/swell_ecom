module SwellEcom

	class SubscriptionService

		def initialize( args = {} )

			@order_service			= args[:order_service]
			@order_service			||= SwellEcom::OrderService.new

			@transaction_service	= args[:transaction_service]
			@transaction_service	||= SwellEcom.transaction_service_class.constantize.new( SwellEcom.transaction_service_config )

			@default_subscription_class = ( args[:default_subscription_class] || SwellEcom.default_subscription_class.constantize )

		end

		def subscribe_ordered_item( order_item, args = {} )

			self.subscribe( order_item.order.user, order_item.item, args.merge( quantity: order_item.quantity, order: order_item.order ) )

		end

		def subscribe_ordered_plans( order, args = {} )
			# will only create plans for active orders
			raise Exception.new('Can only create subscriptions for active orders') unless order.active?

			order.order_items.each do |order_item|
				if order_item.item.is_a? SwellEcom::SubscriptionPlan

					order_item.subscription ||= self.subscribe_ordered_item( order_item, args )
					order_item.save

				end
			end

		end

		def subscribe( user, plan, args = {} )
			subscription_class = ( args[:subscription_class] || @default_subscription_class )
			start_at = args[:start_at] || Time.now
			quantity = args[:quantity] || 1

			if (order = args[:order]).present?

				args[:billing_address]	||= order.billing_address
				args[:shipping_address]	||= order.shipping_address
				args[:currency]			||= order.currency
				args[:provider]			||= order.provider
				args[:provider_customer_profile_reference] ||= order.provider_customer_profile_reference
				args[:provider_customer_payment_profile_reference] ||= order.provider_customer_payment_profile_reference

				args[:discount] = order.order_items.discount.first.try(:item)

				if ( charge_transaction = order.transactions.charge.approved.first ).present? && charge_transaction.respond_to?( :properties )

					args[:credit_card_ending_in]	||= charge_transaction.properties['credit_card_ending_in']
					args[:credit_card_brand]		||= charge_transaction.properties['credit_card_brand']

				end

			end

			discount = SwellEcom::Discount.find_by( args.delete(:discount_id) ) if args[:discount_id]
			discount ||= args[:discount]
			discount = nil unless discount.try(:for_subscriptions?)

			args[:trial_price]	||= args[:trial_amount] / quantity if args[:trial_amount]
			args[:price]		||= args[:amount] / quantity if args[:amount]
			args[:trial_price]	||= plan.trial_price
			args[:price]		||= plan.price

			args[:trial_amount]	||= args[:trial_price] * quantity
			args[:amount]		||= args[:price] * quantity

			args[:currency]		||= 'USD'

			trial_interval = plan.trial_interval_value.try( plan.trial_interval_unit )
			billing_interval = plan.billing_interval_value.try( plan.billing_interval_unit )

			current_period_end_at = start_at + billing_interval

			if plan.trial?
				trial_start_at = start_at
				trial_end_at = trial_start_at + trial_interval * plan.trial_max_intervals
				current_period_end_at = start_at + trial_interval
			end

			subscription = subscription_class.new(
				user: user,
				subscription_plan: plan,
				billing_address: args[:billing_address],
				shipping_address: args[:shipping_address],
				quantity: quantity,
				status: 'active',
				start_at: start_at,
				trial_start_at: trial_start_at,
				trial_end_at: trial_end_at,
				current_period_start_at: start_at,
				current_period_end_at: current_period_end_at,
				next_charged_at: current_period_end_at,
				billing_interval_value: plan.billing_interval_value,
				billing_interval_unit: plan.billing_interval_unit,
				currency: args[:currency],
				discount: discount,
				provider: args[:provider],
				provider_customer_profile_reference: args[:provider_customer_profile_reference],
				provider_customer_payment_profile_reference: args[:provider_customer_payment_profile_reference],
				payment_profile_expires_at: args[:payment_profile_expires_at],
				trial_amount: args[:trial_amount],
				amount: args[:amount],
				trial_price: args[:trial_price],
				price: args[:price],
			)

			if subscription.respond_to? :properties
				subscription.properties = {
					'credit_card_ending_in'	=> args[:credit_card_ending_in],
					'credit_card_brand'		=> args[:credit_card_brand],
				}
			end

			subscription.save!

			subscription
		end

		def charge_subscription( subscription, args = {} )
			time_now = args[:now] || Time.now

			raise Exception.new("Subscription #{subscription.id } isn't ready to renew yet.  Currently it's #{time_now}, but subscription doesn't renew until #{subscription.next_charged_at}") unless subscription.next_charged_at < time_now
			raise Exception.new("Subscription #{subscription.id } isn't active, so can't be charged.") unless subscription.active?

			# create order
			plan = subscription.subscription_plan

			order = Order.new(
				billing_address: subscription.billing_address,
				shipping_address: subscription.shipping_address,
				user: subscription.user,
				generated_by: 'system_generaged',
				parent: subscription,
				email: subscription.user.email,
				currency: subscription.currency,
				provider: subscription.provider,
				provider_customer_profile_reference: subscription.provider_customer_profile_reference,
				provider_customer_payment_profile_reference: subscription.provider_customer_payment_profile_reference,
			)

			interval = nil

			if subscription.is_next_interval_a_trial?
				interval = plan.trial_interval_value.try(plan.trial_interval_unit)

				order.order_items.new item: subscription, subscription: subscription, price: subscription.trial_price, sku: plan.trial_sku, subtotal: subscription.trial_amount, order_item_type: 'prod', quantity: subscription.quantity, title: plan.title, tax_code: plan.tax_code
			else
				interval = subscription.billing_interval_value.try(subscription.billing_interval_unit)

				order.order_items.new item: subscription, subscription: subscription, price: subscription.price, sku: plan.product_sku, subtotal: subscription.amount, order_item_type: 'prod', quantity: subscription.quantity, title: plan.title, tax_code: plan.tax_code
			end

			# apply the subscription discount to new orders
			discount = subscription.discount
			order.order_items.new( item: discount, order_item_type: 'discount', title: discount.title ) if discount.present? && discount.active? && discount.in_progress?( now: time_now )

			# process order
			transaction = @order_service.process( order )

			# handle response
			if order.nested_errors.present? || !transaction || not( transaction.approved? )

				if transaction.present? && transaction.persisted?

					transaction.parent_obj = subscription
					transaction.save

				else

					# if no transaction was created, create one to log the error
					transaction = SwellEcom::Transaction.create(
						message: order.nested_errors.join(' * '),
						parent_obj: subscription,
						status: 'declined',
						transaction_type: 'charge',
						amount: order.total,
						currency: order.currency,
					)

				end

				# annotate how, how often, and when the subscription failed
				subscription.failed_attempts = subscription.failed_attempts + 1 if subscription.respond_to? :failed_attempts
				subscription.failed_message = transaction.message if subscription.respond_to? :failed_message
				subscription.failed_at = transaction.created_at if subscription.respond_to? :failed_at

				# mark subscription as failed if the transaction failed
				subscription.status = 'failed'

				subscription.save

				order.errors.add(:base, :processing_error, message: 'Transaction failed') if !transaction || not( transaction.approved? )

			else
				order.save

				# remove discount after use, if it is not for more than one order
				subscription.discount = nil unless subscription.discount.try(:for_subscriptions?)

				subscription.failed_attempts = 0 if subscription.respond_to? :failed_attempts

				# update the subscriptions next date
				subscription.current_period_start_at = subscription.next_charged_at
				subscription.current_period_end_at = subscription.current_period_start_at + interval
				subscription.next_charged_at = subscription.next_charged_at + interval
				subscription.save

			end

			order

		end

		def update_payment_profile( subscription, args = {} )
			@transaction_service.update_subscription_payment_profile( subscription, args )
		end

	end


end
