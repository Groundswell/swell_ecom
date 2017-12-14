module SwellEcom
	class OrderAdminController < SwellMedia::AdminController

		before_filter :get_order, except: [ :index ]

		def address
			address_attributes = params.require( :geo_address ).permit( :first_name, :last_name, :geo_country_id, :geo_state_id, :street, :street2, :city, :zip, :phone )
			address = GeoAddress.create( address_attributes.merge( user: @order.user ) )

			if address.errors.present?

				set_flash address.errors.full_messages, :danger

			else

				attribute_name = params[:attribute] == 'billing_address' ? 'billing_address' : 'shipping_address'
				@order.update( attribute_name => address )

				set_flash "Address Updated", :success

			end
			redirect_to :back
		end

		def edit
			@transactions = Transaction.where( parent_obj: @order )


			@billing_countries 	= SwellEcom::GeoCountry.all
			@shipping_countries = SwellEcom::GeoCountry.all

			@billing_countries = @billing_countries.where( abbrev: SwellEcom.billing_countries[:only] ) if SwellEcom.billing_countries[:only].present?
			@billing_countries = @billing_countries.where( abbrev: SwellEcom.billing_countries[:except] ) if SwellEcom.billing_countries[:except].present?

			@shipping_countries = @shipping_countries.where( abbrev: SwellEcom.shipping_countries[:only] ) if SwellEcom.shipping_countries[:only].present?
			@shipping_countries = @shipping_countries.where( abbrev: SwellEcom.shipping_countries[:except] ) if SwellEcom.shipping_countries[:except].present?

			@billing_states 	= SwellEcom::GeoState.where( geo_country_id: @order.shipping_address.try(:geo_country_id) || @billing_countries.first.id ) if @billing_countries.count == 1
			@shipping_states	= SwellEcom::GeoState.where( geo_country_id: @order.billing_address.try(:geo_country_id) || @shipping_countries.first.id ) if @shipping_countries.count == 1

		end

		def index
			sort_by = params[:sort_by] || 'created_at'
			sort_dir = params[:sort_dir] || 'desc'

			@orders = Order.order( "#{sort_by} #{sort_dir}" )

			if params[:status].present? && params[:status] != 'all'
				@orders = eval "@orders.#{params[:status]}"
			end

			if params[:q].present?
				@orders = @orders.where( "email like :q", q: "'%#{params[:q].downcase}%'" )
			end

			@orders = @orders.page( params[:page] )
		end

		def refund
			refund_amount = ( params[:amount].to_f * 100 ).to_i

			# check that refund amount doesn't exceed charges?
			# amount_net = Transaction.approved.positive.where( parent: @order ).sum(:amount) - Transaction.approved.negative.where( parent: @order ).sum(:amount)

			@transaction_service = SwellEcom.transaction_service_class.constantize.new( SwellEcom.transaction_service_config )

			@transaction = @transaction_service.refund( amount: refund_amount, order: @order )

			if @transaction.errors.present?

				set_flash @transaction.errors.full_messages, :danger

			elsif @transaction.declined?

				set_flash @transaction.message, :danger

			else

				@order.refunded!
				# OrderMailer.refund( @transaction ).deliver_now # send emails on a cron
				set_flash "Refund successful", :success

			end

			redirect_to swell_ecom.edit_order_admin_path( @order )
		end


		def update
			@order.attributes = order_params

			if @order.status_changed? && ( @order.status == 'fulfilled' && @order.status_was == 'placed' )
				@order.fulfilled_at = Time.zone.now
			end
			@order.save
			redirect_to :back
		end

		private
			def order_params
				params.require( :order ).permit( :email, :status, :support_notes )
			end

			def get_order
				@order = Order.find_by( id: params[:id] )
			end

	end
end
