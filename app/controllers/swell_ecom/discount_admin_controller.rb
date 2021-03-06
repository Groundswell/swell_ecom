module SwellEcom
	class DiscountAdminController < SwellEcom::EcomAdminController


		before_action :get_discount, except: [ :create, :index ]
		before_action :init_search_service, only: [:index]

		def create
			authorize( SwellEcom::Discount )

			@discount = Discount.new( discount_params )
			@discount.status = 'draft'
			@discount.start_at = Time.now
			@discount.discount_items.new( discount_amount: 0 )

			if @discount.save
				set_flash 'Discount Created'
				redirect_to edit_discount_admin_path( @discount )
			else
				set_flash 'Discount could not be created', :error, @discount
				redirect_back fallback_location: '/admin'
			end
		end

		def destroy
			authorize( @discount )
			@discount.archive!
			set_flash 'Discount archived'
			redirect_to discount_discount_admin_index_path
		end

		def edit
			authorize( @discount )
			set_page_meta( title: "#{@discount.title || @discount.code} | Discount" )
		end


		def index
			authorize( SwellEcom::Discount )

			sort_by = params[:sort_by] || 'created_at'
			sort_dir = params[:sort_dir] || 'desc'

			filters = ( params[:filters] || {} ).select{ |attribute,value| not( value.nil? ) }
			filters[ params[:status] ] = true if params[:status].present? && params[:status] != 'all'
			@discounts = @search_service.discount_search( params[:q], filters, page: params[:page], order: { sort_by => sort_dir } )

			set_page_meta( title: "Discounts" )
		end

		def update
			authorize( @discount )

			@discount.attributes = discount_params
			@discount.first_discount_item.discount_amount = @discount.first_discount_item.discount_amount / 100 if @discount.first_discount_item.percent?


			if @discount.save && @discount.first_discount_item.save
				set_flash "Discount Updated", :success
			else
				set_flash @discount.errors.full_messages, :danger
			end
			redirect_to edit_discount_admin_path( @discount )
		end

		protected

			def discount_params
				params.require( :discount ).permit( :start_at, :end_at, :status, :title, :code, :description, :availability, :minimum_prod_subtotal_as_money, :minimum_tax_subtotal_as_money, :minimum_shipping_subtotal_as_money, :limit_per_customer, :limit_global, first_discount_item_attributes: [ :discount_type, :discount_amount_as_money, :maximum_orders, :minimum_orders, :order_item_type ] )
			end

			def get_discount
				@discount = Discount.find( params[:id] )
			end

			def init_search_service
				@search_service = EcomSearchService.new
			end

	end
end
