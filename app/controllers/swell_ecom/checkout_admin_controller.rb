
module SwellEcom
	class CheckoutAdminController < SwellEcom::EcomAdminController
		include SwellEcom::Concerns::CheckoutConcern

		before_action :initialize_services, only: [ :confirm, :create, :index, :calculate ]
		before_action :get_order, only: [ :confirm, :create, :index, :calculate ]
		before_action :get_geo_addresses, only: :index

		def confirm

			@order_service.calculate( @order,
				transaction: transaction_options,
				shipping: shipping_options,
			)

		end

		def calculate

			@shipping_service = SwellEcom.shipping_service_class.constantize.new( SwellEcom.shipping_service_config )

			@shipping_rates = []

			begin

				@order_service.calculate( @order,
					transaction: transaction_options,
					shipping: shipping_options,
				)

				@shipping_rates = @shipping_service.find_rates( @order, shipping_options ) if @order.shipping_address.geo_country.present?
			rescue Exception => e
				puts e
			end
		end

		def create

			@order_service.process( @order,
				transaction: transaction_options,
				shipping: shipping_options,
			)

			if params[:newsletter].present?
				SwellMedia::Optin.create(
					email: @order.email,
					name: "#{@order.billing_address.first_name} #{@order.billing_address.last_name}",
					ip: @order.ip,
					user: @order.user
				)
			end


			if @order.errors.present?
				set_flash @order.errors.full_messages, :danger
				respond_to do |format|
					format.json {
						render :create
					}
					format.html {
						redirect_back fallback_location: '/checkout_admin'
					}
				end
			else

				payment_profile_expires_at = SwellEcom::TransactionService.parse_credit_card_expiry( params[:credit_card][:expiration] ) if params[:credit_card].present?
				@subscription_service.subscribe_ordered_plans( @order, payment_profile_expires_at: payment_profile_expires_at ) if @order.active?

				# if current user exists, update it's address info with the
				# billing address, if not already set
				update_order_user_address( @order )

				OrderMailer.receipt( @order ).deliver_now


				respond_to do |format|
					format.json {
						render :create
					}
					format.html {
						redirect_to swell_ecom.thank_you_order_path( @order.code )
					}
				end

			end


		end

		def index

		end


		protected

		def get_order

			@order = Order.new( get_order_attributes )
			@order.billing_address.user = @order.shipping_address.user = @order.user = @user

			discount = Discount.active.in_progress.find_by( code: params[:coupon] ) if params[:coupon].present?
			order_item = @order.order_items.new( item: discount, order_item_type: 'discount', title: discount.title ) if discount.present?

		end



	end
end
