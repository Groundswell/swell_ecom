# require 'ups'
# https://github.com/ptrippett/ups
# install 'ups' gem

module SwellEcom

	module ShippingServices

		class UPSShippingService < SwellEcom::ShippingService

			def initialize( args = {} )

				super( args )

				@ship_from	= args[:ship_from]
				@shipper	= args[:shipper]

				@test_mode = not( Rails.env.production? )
				@test_mode = args[:test_mode] if args.has_key? :test_mode

				@api_key	= args[:api_key] || ENV["UPS_LICENSE_NUMBER"]
				@username	= args[:username] || ENV["UPS_USER_ID"]
				@password	= args[:password] || ENV["UPS_PASSWORD"]

				@server = UPS::Connection.new(test_mode: @test_mode)

			end

			def fetch_delivery_status_for_code( code, args = {} )
				return false
			end

			def process( order, args = {} )
				return false
			end

			protected
			def request_address_rates( geo_address, line_items, args = {} )

				begin
					response = server.rates do |rate_builder|
						rate_builder.add_access_request @api_key, @username, @password

						rate_builder.add_shipper ( args[:shipper] || @shipper )
						rate_builder.add_ship_from ( args[:ship_from] || @ship_from )
						rate_builder.add_ship_to phone_number: geo_address.phone,
							address_line_1: geo_address.street,
							address_line_2: geo_address.street2,
							city: geo_address.city,
							state: geo_address.state_name,
							postal_code: geo_address.zip,
							country: geo_address.geo_country.abbrev

						line_items.each do |line_item|
							# convert from grams to KGs
							package_weight_kgs = (line_item.package_weight * 0.001)

							rate_builder.add_package weight: package_weight_kgs.to_s, unit: 'KGS'
						end
					end

					if response.success?

						rates = response.rated_shipments.collect do |rate|
							{ name: rate[:service_name], code: rate[:service_code], price: (rate[:total].to_f * 100.o).to_i, carrier: 'UPS', currency: 'USD' }
						end

					else

						rates = []

					end

				rescue Exception => e

					NewRelic::Agent.notice_error(e) if defined?( NewRelic )
					rates = []
				end

				rates
			end

		end

	end

end