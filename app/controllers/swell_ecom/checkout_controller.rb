
module SwellEcom
	class CheckoutController < ApplicationController
		include CheckoutComposition
		include PayPalCheckoutHelper

		before_action :get_cart
		before_action :initialize_checkout_services, only: [ :confirm, :create, :index ]
		before_action :get_order, only: [ :confirm, :create, :index ]

		def confirm

			@order_service.calculate( @order, transaction: transaction_options )

		end

		def create

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

				# if current user exists, update it's address info with the
				# billing address, if not already set
				current_user.update( address1: (current_user.address1 || @order.billing_address.street), address2: (current_user.address2 || @order.billing_address.street2), city: (current_user.city || @order.billing_address.city), state: (current_user.state || @order.billing_address.state_abbrev), zip: (current_user.zip || @order.billing_address.zip), phone: (current_user.phone || @order.billing_address.phone) ) if current_user.present?

				@cart.update( order_id: @order.id, status: 'success' )

				OrderMailer.receipt( @order ).deliver_now
				#OrderMailer.notify_admin( @order ).deliver_now

				redirect_to swell_ecom.thank_you_order_path( @order.code )

			end


		end

		def index

			@billing_countries 	= SwellEcom::GeoCountry.all
			@shipping_countries = SwellEcom::GeoCountry.all

			@billing_countries = @billing_countries.where( abbrev: SwellEcom.billing_countries[:only] ) if SwellEcom.billing_countries[:only].present?
			@billing_countries = @billing_countries.where( abbrev: SwellEcom.billing_countries[:except] ) if SwellEcom.billing_countries[:except].present?

			@shipping_countries = @shipping_countries.where( abbrev: SwellEcom.shipping_countries[:only] ) if SwellEcom.shipping_countries[:only].present?
			@shipping_countries = @shipping_countries.where( abbrev: SwellEcom.shipping_countries[:except] ) if SwellEcom.shipping_countries[:except].present?

			@billing_states 	= SwellEcom::GeoState.where( geo_country_id: @order.shipping_address.try(:geo_country_id) || @billing_countries.first.id ) if @billing_countries.count == 1
			@shipping_states	= SwellEcom::GeoState.where( geo_country_id: @order.billing_address.try(:geo_country_id) || @shipping_countries.first.id ) if @shipping_countries.count == 1

			@cart.init_checkout!

			add_page_event_data(
				ecommerce: {
					checkout: {
						actionField: {},
						products: @cart.cart_items.collect{|cart_item| cart_item.item.page_event_data.merge( quantity: cart_item.quantity ) }
					}
				}
			);

		end

		def new
			redirect_to checkout_index_path( params.permit(:stripeToken, :credit_card, :coupon, :order ).to_h.merge( controller: nil, action: nil ) )
		end

		def state_input

			@order = Order.new currency: 'usd'
			@order.shipping_address = GeoAddress.new
			@order.billing_address 	= GeoAddress.new

			@address_attribute = ( params[:address_attribute] == 'billing_address' ? :billing_address : :shipping_address )
			@states = SwellEcom::GeoState.where( geo_country_id: params[:geo_country_id] )

			render layout: false

		end


		protected
		def initialize_checkout_services
			@order_service = SwellEcom::OrderService.new
			@subscription_service = SwellEcom::SubscriptionService.new( order_service: @order_service )
		end

		def transaction_options
			params.slice( :stripeToken, :credit_card )
		end

	end
end
