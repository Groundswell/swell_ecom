module SwellEcom

	class EcomSearchService

		def search( term, filters = {}, options = {} )

			addresses = self.address_search( term, filters[:address] || {}, options )
			customers = self.customer_search( term, filters[:customer] || {}, options.merge( addresses: addresses ) )
			subscriptions = self.subscription_search( term, filters[:subscription] || {}, options.merge( addresses: addresses, customers: customers ) )
			orders = self.order_search( term, filters[:order] || {}, options.merge( addresses: addresses, customers: customers ) )

			{
				addresses: addresses,
				customers: customers,
				subscriptions: subscriptions,
				orders: orders,
			}
		end

		def customer_search( term, filters = {}, options = {} )
			users = SwellMedia.registered_user_class.constantize.all

			users = users.where( id: SwellEcom::Order.select(:user_id) ) # @todo replace with a more elegant mechanism.  this one is not scalable

			if term.present?
				query = "%#{term.gsub('%','\\\\%')}%"

				addresses = options[:addresses] || self.address_search( term )
				users = SwellMedia.registered_user_class.constantize.where( "name ILIKE :q OR (first_name || ' ' || last_name) ILIKE :q OR email ILIKE :q OR phone ILIKE :q OR users.id IN ( :user_ids )", q: query, user_ids: addresses.select(:user_id) )
			end

			return self.apply_options_and_filters( users, filters, options )
		end

		def address_search( term, filters = {}, options = {} )
			addresses = GeoAddress.all

			if term.present?
				query = "%#{term.gsub('%','\\\\%')}%"

				addresses = addresses.where( "street ILIKE :q OR phone ILIKE :q OR (first_name || '' || last_name) ILIKE :q ", q: query )
			end

			return self.apply_options_and_filters( addresses, filters, options )
		end

		def order_search( term, filters = {}, options = {} )
			orders = Order.all

			if term.present?
				query = "%#{term.gsub('%','\\\\%')}%"

				addresses = options[:addresses] || self.address_search( term )
				users = options[:customers] || self.customer_search( term, {}, addresses: addresses )

				orders = orders.where( "email ILIKE :q OR code ILIKE :q OR billing_address_id IN (:address_ids) OR shipping_address_id IN (:address_ids) OR user_id IN (:user_ids)", q: query, address_ids: addresses.select(:id), user_ids: users.select(:id) )
			end

			return self.apply_options_and_filters( orders, filters, options )
		end

		def product_search( term, filters = {}, options = {} )
			products = SwellEcom::Product.all

			if term.present?
				query = "%#{term.gsub('%','\\\\%')}%"

				products = products.where( "title ILIKE :q OR description ILIKE :q", q: query )
			end

			return self.apply_options_and_filters( products, filters, options )
		end

		def subscription_plan_search( term, filters = {}, options = {} )
			plans = SwellEcom::SubscriptionPlan.all

			if term.present?
				query = "%#{term.gsub('%','\\\\%')}%"

				plans = plans.where( "title ILIKE :q OR description ILIKE :q", q: query )
			end

			return self.apply_options_and_filters( plans, filters, options )
		end

		def subscription_search( term, filters = {}, options = {} )
			subscriptions = Subscription.all

			if term.present?
				query = "%#{term.gsub('%','\\\\%')}%"

				addresses = options[:addresses] || self.address_search( term )
				users = options[:customers] || self.customer_search( term, {}, addresses: addresses )

				subscriptions = subscriptions.where( "code ILIKE :q OR billing_address_id IN (:address_ids) OR shipping_address_id IN (:address_ids) OR user_id IN (:user_ids)", q: query, address_ids: addresses.select(:id), user_ids: users.select(:id) )
			end

			return self.apply_options_and_filters( subscriptions, filters, options )
		end

		protected
		def apply_options_and_filters( relation, filters, options )

			filters.each do | key, value |
				if relation.respond_to?( key ) && value
					relation = relation.try( key )
				else
					relation = relation.where( key => value )
				end
			end

			options[:order] = [options[:order]] if options[:order].is_a? Hash
			if options[:order].is_a? Array

				options[:order].each do |order_option|

					relation = relation.order( order_option.keys.first => order_option.values.first )
				end
			end

			relation = relation.page( options[:page] ) if options.has_key? :page
			relation = relation.per( options[:per] ) if options.has_key? :per

			relation

		end

	end

end
