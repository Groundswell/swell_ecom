
module SwellEcom

	module TransactionServices

		class PayPalCheckoutTransactionService < SwellEcom::TransactionService

			PAYMENTS_ENDPOINT = 'https://api.sandbox.paypal.com/v1/payments/payment'
			EXECUTE_PAYMENT_ENDPOINT = 'https://api.sandbox.paypal.com/v1/payments/payment/{payment_id}/execute/'

			def initialize( args = {} )
				@provider_name = args[:provider_name] || "PayPalExpress"
				@paypal_host = args[:paypal_host] || ENV['PAYPAL_EXPRESS_HOST']
				@environment = args[:environment] || ( ENV['PAYPAL_EXPRESS_ENVIRONMENT'] == 'production' ? 'production' || 'sandbox' )
				@access_token = args[:access_token] || ENV['PAYPAL_EXPRESS_ACCESS_TOKEN']

				@experience_profile_id = args[:experience_profile_id] || ENV['PAYPAL_EXPRESS_EXPERIENCE_PROFILE_ID']
				@return_url = args[:return_url]
				@cancel_url = args[:cancel_url]
			end

			def capture_payment_method( order, args = {} )

			end

			def environment
				@environment
			end

			def generate_payment( order, args = {} )

				order.provider = provider_name

				payload = build_payment_request( order, args = {} ).to_json
				response_string = RestClient.post( PAYMENTS_ENDPOINT, payload, 'Authorization' => "Bearer #{@access_token}" )
				response_json = JSON.parse response_string, symbolize_names: true

				if response_json[:state] == 'created'
					order.provider_customer_payment_profile_reference = response_json[:id]
				else
					nil
				end
			end

			def process( order, args = {} )

				endpoint = EXECUTE_PAYMENT_ENDPOINT.gsub('{payment_id}',args[:paymentID])
				payload = { payer_id: args[:payerID] }.to_json

				response_string = RestClient.post( PAYMENTS_ENDPOINT, payload, 'Authorization' => "Bearer #{@access_token}" )
				response_json = JSON.parse response_string, symbolize_names: true

				transaction = SwellEcom::Transaction.new(
					parent_obj: order,
					transaction_type: 'charge',
					reference_code: direct_response.transaction_id,
					customer_profile_reference: args[:payerID],
					provider_customer_payment_profile_reference: args[:paymentID],
					provider: provider_name,
					amount: order.total,
					currency: order.currency,
					status: 'declined'
				)

				order.provider = transaction.provider
				order.provider_customer_profile_reference = transaction.provider_customer_profile_reference
				order.provider_customer_payment_profile_reference = transaction.provider_customer_payment_profile_reference

				if response_json[:state] == 'approved'
					payer_info = response_json[:payer][:payer_info]

					order.email = payer_info[:email]
					order.billing_address.first_name = payer_info[:first_name]
					order.billing_address.last_name = payer_info[:last_name]
					order.billing_address.email = payer_info[:email]

					transaction.status = 'approved'

					if response_json[:intent] == 'sale'

						order.payment_status = 'paid'
						transaction.transaction_type = 'charge'

					elsif response_json[:intent] == 'order'

						order.payment_status = 'payment_method_captured'
						transaction.transaction_type = 'preauth'

					end


				else

					transaction.status = 'declined'
					# transaction.message = error message here

					order.payment_status = 'declined'
					order.errors.add(:base, :processing_error, message: "Transaction declined.")

				end

				transaction.save

				transaction
			end

			def provider_name
				@provider_name
			end

			end

			def refund( args = {} )

			end

			def update_subscription_payment_profile( subscription, args = {} )

			end

			protected

			def build_payment_request( order, args = {} )
				# https://developer.paypal.com/docs/integration/direct/express-checkout/integration-jsv4/advanced-payments-api/create-express-checkout-payments/

				intent = 'sale'
				intent = 'order' if order.pre_order?

				prod_order_items = order.order_items.select{|oi| oi.prod? }
				discount_order_items = order.order_items.select{|oi| oi.discount? }
				shipping = order.order_items.select{|oi| oi.shipping? }.sum(&:subtotal_as_money)
				tax = order.order_items.select{|oi| oi.tax? }.sum(&:subtotal_as_money)

				return {
					"intent": intent,
					"experience_profile_id": (args[:experience_profile_id] || @experience_profile_id),
					"redirect_urls":
					{
						"return_url": (args[:return_url] || @return_url),
						"cancel_url": (args[:cancel_url] || @cancel_url),
					},
					"payer":
					{
						"payment_method": "paypal"
					},
					"transactions": [
					{
						"amount":
						{
							"total": order.total_as_money,
							"currency": order.currency,
							"details":
							{
								"subtotal": order.total_as_money - shipping - tax,
								"shipping": shipping,
								"tax": tax,
							}
						},
						"item_list":
						{
							"items": (prod_order_items + discount_order_items).collect{ |order_item|
								{
									"quantity": order_item.quantity,
									"name": order_item.title,
									"price": order_item.subtotal_as_money,
									"currency": order.currency,
									# "description": "item 1 description",
									# "tax": "1"
								}
							}
						},
						# "description": "The payment transaction description.",
						"invoice_number": order.code,
						# "custom": "merchant custom data"
					}]
				}
			end

		end

	end

end
