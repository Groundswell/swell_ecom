require 'taxjar'

module SwellEcom

	module TaxServices

		class TaxJarTaxService

			def initialize( args = {} )

				@client = Taxjar::Client.new(
					api_key: args[:api_key] || ENV['TAX_JAR_API_KEY']
				)

				@warehouse_address = args[:warehouse] || SwellEcom.warehouse_address
				@origin_address = args[:origin] || SwellEcom.origin_address
				@nexus_address = args[:nexus] || SwellEcom.nexus_address

			end

			def calculate( obj, args = {} )

				return self.calculate_order( obj ) if obj.is_a? Order
				return self.calculate_cart( obj ) if obj.is_a? Cart

			end

			protected

			def calculate_cart( cart )
				# don't know shipping address, so can't calculate
			end

			def calculate_order( order )

				shipping_amount = order.order_items.shipping.sum(:subtotal) / 100.0
				order_total = order.order_items.prod.sum(:subtotal) / 100.0

				nexus_addresses = []
				if @nexus_address.present?
					nexus_addresses << {
						:address_id => @nexus_address[:address_id],
						:country => @nexus_address[:country],
						:zip => @nexus_address[:zip],
						:state => @nexus_address[:state],
						:city => @nexus_address[:city],
						:street => @nexus_address[:street]
					}
				end

				line_items = []
				order.order_items.each do |order_item|
					if order_item.prod?
						line_items << {
							:quantity => order_item.quantity,
							:unit_price => (order_item.price / 100.0),
							:product_tax_code => order_item.tax_code,
						}
					end
				end

				order_info = {
				    :to_country => order.shipping_address.geo_country.abbrev,
				    :to_zip => order.shipping_address.zip,
				    :to_city => order.shipping_address.city,
				    :to_state => order.shipping_address.geo_state.abbrev,
				    :from_country => @warehouse_address[:country] || @origin_address[:country],
				    :from_zip => @warehouse_address[:zip] || @origin_address[:zip],
				    :from_city => @warehouse_address[:city] || @origin_address[:city],
				    :from_state => @warehouse_address[:state] || @origin_address[:state],
				    :amount => order_total - shipping_amount,
				    :shipping => shipping_amount,
				    :nexus_addresses => nexus_addresses,
				    :line_items => line_items,
				}

				tax_for_order = @client.tax_for_order( order_info )
				tax_breakdown = tax_for_order.breakdown
				tax_geo = nil

				# puts tax_for_order.to_json

				if tax_for_order.tax_source == 'destination'
					tax_geo = { country: order_info[:from_country], state: order_info[:from_state], city: order_info[:from_city] }
				elsif tax_for_order.tax_source == 'origin'
					tax_geo = { country: order_info[:from_country], state: order_info[:from_state], city: order_info[:from_city] }
				end

				tax_order_items = []

				tax_order_items << order.order_items.new( subtotal: (tax_breakdown.country_tax_collectable * 100).to_i, title: "Tax (#{tax_geo[:country]})", order_item_type: 'tax' ) if tax_breakdown.country_tax_collectable.present? && tax_breakdown.country_tax_collectable != 0.0
				tax_order_items << order.order_items.new( subtotal: (tax_breakdown.state_tax_collectable * 100).to_i, title: "Tax (#{tax_geo[:state]})", order_item_type: 'tax' ) if tax_breakdown.state_tax_collectable.present? && tax_breakdown.state_tax_collectable != 0.0
				tax_order_items << order.order_items.new( subtotal: (tax_breakdown.city_tax_collectable * 100).to_i, title: "Tax (#{tax_geo[:city]})", order_item_type: 'tax' ) if tax_breakdown.city_tax_collectable.present? && tax_breakdown.city_tax_collectable != 0.0
				tax_order_items << order.order_items.new( subtotal: (tax_breakdown.special_district_tax_collectable * 100).to_i, title: "Taxes (district)", order_item_type: 'tax' ) if tax_breakdown.special_district_tax_collectable.present? && tax_breakdown.special_district_tax_collectable != 0.0

				tax_order_items << order.order_items.new( subtotal: (tax_breakdown.gst * 100).to_i, title: "Tax (GST)", order_item_type: 'tax' ) if tax_breakdown.gst.present? && tax_breakdown.gst != 0.0
				tax_order_items << order.order_items.new( subtotal: (tax_breakdown.pst * 100).to_i, title: "Tax (PST)", order_item_type: 'tax' ) if tax_breakdown.pst.present? && tax_breakdown.pst != 0.0
				tax_order_items << order.order_items.new( subtotal: (tax_breakdown.qst * 100).to_i, title: "Tax (QST)", order_item_type: 'tax' ) if tax_breakdown.qst.present? && tax_breakdown.qst != 0.0


				return order

			end

		end

	end

end
