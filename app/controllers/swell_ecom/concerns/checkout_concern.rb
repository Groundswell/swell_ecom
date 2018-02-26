module SwellEcom
	module Concerns

		module CheckoutConcern
			extend ActiveSupport::Concern

			def update_order_user_address( order )

				# if order user exists, update it's address info with the
				# billing address, if not already set
				if order.user.present?
					order.user.update(
						address1: (order.user.address1 || order.billing_address.street),
						address2: (order.user.address2 || order.billing_address.street2),
						city: (order.user.city || order.billing_address.city),
						state: (order.user.state || order.billing_address.state_abbrev),
						zip: (order.user.zip || order.billing_address.zip),
						phone: (order.user.phone || order.billing_address.phone)
					)
				end

			end

			def get_order_attributes
				order_attributes = params.permit(
					order: [
						:email,
						:customer_notes,
						:same_as_billing,
						{
							:billing_address => [
								:phone, :zip, :geo_country_id, :geo_state_id , :state, :city, :street2, :street, :last_name, :first_name,
							],
							:shipping_address => [
								:phone, :zip, :geo_country_id, :geo_state_id , :state, :city, :street2, :street, :last_name, :first_name,
							],
							:order_items => [
								:item_type,
								:item_id,
								:quantity,
							],
							:billing_address_attributes => [
								:phone, :zip, :geo_country_id, :geo_state_id , :state, :city, :street2, :street, :last_name, :first_name,
							],
							:shipping_address_attributes => [
								:phone, :zip, :geo_country_id, :geo_state_id , :state, :city, :street2, :street, :last_name, :first_name,
							],
							:order_items_attributes => [
								:item_type,
								:item_id,
								:quantity,
							],
						},
					]
				).to_h

				order_attributes = order_attributes[:order] || {}

				order_attributes[:billing_address_attributes]	||= order_attributes.delete(:billing_address) || {}
				order_attributes[:shipping_address_attributes]	||= order_attributes.delete(:shipping_address) || {}
				order_attributes[:order_items_attributes]		||= order_attributes.delete(:order_items) || []

				order_attributes[:shipping_address_attributes] ||= order_attributes[:billing_address_attributes] if order_attributes.delete(:same_as_billing)

				order_attributes[:order_items_attributes] ||= []
				if order_attributes[:order_items_attributes].present?
					order_attributes[:order_items_attributes].each do |order_item|
						order_item[:order_item_type] 	= 'prod'
						order_item[:item]				= order_item[:item_type].constantize.find_by( id: order_item[:item_id] )
						order_item[:title]				= order_item[:item].title
						order_item[:price]				= order_item[:item].price
						order_item[:price]				= order_item[:item].trial_price if order_item[:item].is_a?( SubscriptionPlan ) && order_item[:item].trial?
						order_item[:subtotal]			= order_item[:price].to_i * order_item[:quantity].to_i
						order_item[:tax_code]			= order_item[:item].tax_code
					end
				end

				order_attributes[:status]	||= 'active'
				order_attributes[:ip]		||= client_ip
				order_attributes[:currency]	||= 'usd'

				order_attributes

			end

			def initialize_services
				@order_service = SwellEcom::OrderService.new
				@subscription_service = SwellEcom::SubscriptionService.new( order_service: @order_service )
			end

			def shipping_options
				{ ip: client_ip, ip_country: client_ip_country }
			end

			def transaction_options
				params.slice( :stripeToken, :credit_card ).merge({ ip: client_ip, ip_country: client_ip_country })
			end

		end
	end
end
