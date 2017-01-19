module SwellEcom
	class ProductAdminController < SwellMedia::AdminController

		before_filter :get_product, except: [ :create, :index ]
		
		def index
			sort_by = params[:sort_by] || 'publish_at'
			sort_dir = params[:sort_dir] || 'desc'

			@products = Product.order( "#{sort_by} #{sort_dir}" )

			if params[:status].present? && params[:status] != 'all'
				@products = eval "@products.#{params[:status]}"
			end

			if params[:q].present?
				@products = @products.where( "array[:q] && keywords", q: params[:q].downcase )
			end

			@products = @products.page( params[:page] )
		end

		def edit
			
		end

		def update
			@product.slug = nil if params[:update_slug].present? && params[:product][:title] != @product.title

			@product.attributes = product_params
			@product.avatar_urls = params[:product][:avatar_urls] if params[:product].present? && params[:product][:avatar_urls].present?

			if @product.save
				set_flash 'Product Updated'
				redirect_to edit_product_admin_path( id: @product.id )
			else
				set_flash 'Product could not be Updated', :error, @product
				render :edit
			end
		end

		private
			def product_params
				params[:product][:price] = params[:product][:price].gsub( /\D/, '' )
				params[:product][:suggested_price] = params[:product][:suggested_price].gsub( /\D/, '' )
				params.require( :product ).permit( :title, :subtitle, :slug_pref, :description, :content, :price, :suggested_price, :status, :publish_at, :tags, :tags_csv, :avatar, :avatar_asset_file, :avatar_asset_url, :cover_path, :avatar_urls )
			end

			def get_product
				@product = Product.friendly.find( params[:id] )
			end

	end
end