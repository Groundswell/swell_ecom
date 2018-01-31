module SwellEcom
	class DiscountAdminController < SwellMedia::AdminController


		before_action :get_discount, except: [ :create, :index ]

		def create
			authorize( SwellEcom::Discount, :admin_create? )

			@discount = Discount.new( discount_params )
			@discount.status = 'draft'
			@discount.start_at = Time.now
			@discount.discount_items.new()

			if @discount.save
				set_flash 'Discount Created'
				redirect_to edit_discount_admin_path( @discount )
			else
				set_flash 'Discount could not be created', :error, @discount
				redirect_to :back
			end
		end

		def destroy
			authorize( @discount, :admin_destroy? )
			@discount.archive!
			set_flash 'Discount archived'
			redirect_to discount_discount_admin_index_path
		end

		def edit
			authorize( @discount, :admin_edit? )
		end


		def index
			authorize( SwellEcom::Discount, :admin? )

			sort_by = params[:sort_by] || 'created_at'
			sort_dir = params[:sort_dir] || 'desc'

			@discounts = Discount.order( "#{sort_by} #{sort_dir}" )

			if params[:status].present? && params[:status] != 'all' && Discount.statuses[params[:status]].present?
				@discounts = @discounts.try(params[:status])
			end

			@discounts = @discounts.page( params[:page] )
		end

		def update
			authorize( @discount, :admin_update? )

			@discount.attributes = discount_params
			if @discount.save && @discount.first_discount_item.save
				set_flash "Discount Updated", :success
			else
				set_flash @discount.errors.full_messages, :danger
			end
			redirect_to edit_discount_admin_path( @discount )
		end

		private

			def discount_params
				params.require( :discount ).permit( :start_at, :end_at, :status, :title, :description, :availability, :minimum_prod_subtotal_as_money, :minimum_tax_subtotal_as_money, :minimum_shipping_subtotal_as_money, :limit_per_customer, :limit_global, first_discount_item_attributes: [ :discount_type, :discount_amount, :maximum_orders, :minimum_orders, :order_item_type ] )
			end

			def get_discount
				@discount = Discount.find( params[:id] )
			end

	end
end
