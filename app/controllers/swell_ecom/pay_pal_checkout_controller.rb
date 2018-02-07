
module SwellEcom
	class PayPalCheckoutController < ApplicationController
		include CheckoutComposition

		before_action :get_cart
		before_action :initialize_checkout_services
		before_action :get_order, only: [ :create ]

		def create

			@order = SwellEcom::Order.where( created_at: 12.hours.ago..Time.now ).find_by(
				provider_customer_payment_profile_reference: transaction_options[:paymentID],
				user: current_user,
			)

			@order_service.process( @order, transaction: transaction_options )

			if params[:newsletter].present?
				SwellMedia::Optin.create( email: @order.email, name: "#{@order.billing_address.first_name} #{@order.billing_address.last_name}", ip: client_ip, user: current_user )
			end


			if @order.errors.present?
				set_flash @order.errors.full_messages, :danger
				redirect_back fallback_location: '/checkout'
			else
				session[:cart_count] = 0
				session[:cart_id] = nil

				@order.update( status: 'active' )

				# if current user exists, update it's address info with the
				# billing address, if not already set
				current_user.update( address1: (current_user.address1 || @order.billing_address.street), address2: (current_user.address2 || @order.billing_address.street2), city: (current_user.city || @order.billing_address.city), state: (current_user.state || @order.billing_address.state_abbrev), zip: (current_user.zip || @order.billing_address.zip), phone: (current_user.phone || @order.billing_address.phone) ) if current_user.present?

				@cart.update( order_id: @order.id, status: 'success' )

				OrderMailer.receipt( @order ).deliver_now
				#OrderMailer.notify_admin( @order ).deliver_now

				redirect_to swell_ecom.thank_you_order_path( @order.code )

			end

		end

		def new

			if @order.order_items.select{ |order_item| order_item.prod? && order_item.item.is_a? SwellEcom::SubscriptionPlan }
				@message = 'Unable to process subscriptions by PayPal'
				return
			end

			@order_service.calculate( @order )
			@payment_id = @transaction_service.generate_payment( @order )
			@order.status = 'draft'
			@order.save

		end

		protected

		def initialize_checkout_services
			@transaction_service = SwellEcom::PayPalCheckoutTransactionService.new()
			@order_service = SwellEcom::OrderService.new( transaction_service: @transaction_service )
			@subscription_service = SwellEcom::SubscriptionService.new( order_service: @order_service )
		end

		def transaction_options
			params.require( :paymentID, :payerID )
		end

	end
end
