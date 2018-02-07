module SwellEcom::CheckoutComposition
	extend ActiveSupport::Concern

	def get_cart
		@cart ||= Cart.find_by( id: session[:cart_id] )
	end

	def get_order

		if @cart.nil?
			redirect_to '/cart'
			return false
		end

		if params[:order].present?
			order_attributes 			= params.require(:order).permit(:email, :customer_notes)
			order_items_attributes		= params[:order][:order_items]
			billing_address_attributes	= params.require(:order).require(:billing_address ).permit( :phone, :zip, :geo_country_id, :geo_state_id , :state, :city, :street2, :street, :last_name, :first_name )
			shipping_address_attributes = params.require(:order).require(:shipping_address).permit( :phone, :zip, :geo_country_id, :geo_state_id , :state, :city, :street2, :street, :last_name, :first_name )
			shipping_address_attributes = billing_address_attributes if params[:same_as_billing]
		else
			order_attributes = {}
			order_items_attributes		= params[:items]
			shipping_address_attributes = {}
			billing_address_attributes = {}
		end

		@order = Order.new order_attributes.merge( currency: 'usd', user: current_user, ip: client_ip )
		@order.shipping_address = GeoAddress.new shipping_address_attributes.merge( user: current_user )
		@order.billing_address 	= GeoAddress.new billing_address_attributes.merge( user: current_user )

		discount = Discount.active.in_progress.find_by( code: params[:coupon] ) if params[:coupon].present?
		order_item = @order.order_items.new( item: discount, order_item_type: 'discount', title: discount.title ) if discount.present?

		@cart.cart_items.each do |cart_item|
			order_item = @order.order_items.new item: cart_item.item, price: cart_item.price, subtotal: cart_item.subtotal, order_item_type: 'prod', quantity: cart_item.quantity, title: cart_item.item.title, tax_code: cart_item.item.tax_code

			order_item.subscription = @subscription_service.build_subscription( order_item, discount: discount )
			order_item.subscription.payment_profile_expires_at = SwellEcom::TransactionService.parse_credit_card_expiry( params[:credit_card][:expiration] ) if order_item.subscription.present? && params[:credit_card].present?

			@order.status = 'pre_order' if order_item.item.respond_to?( :pre_order? ) && order_item.item.pre_order?

		end

	end

end
