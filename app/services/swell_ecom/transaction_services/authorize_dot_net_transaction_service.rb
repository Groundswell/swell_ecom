require 'authorizenet'

module SwellEcom

	module TransactionServices

		class AuthorizeDotNetTransactionService < SwellEcom::TransactionService

			PROVIDER_NAME = 'Authorize.net'
			ERROR_DUPLICATE_CUSTOMER_PROFILE = 'E00039'
			ERROR_INVALID_PAYMENT_PROFILE = 'E00003'
			CANNOT_REFUND_CHARGE = 'E00027'

			def initialize( args = {} )
				@api_login	= args[:API_LOGIN_ID] || ENV['AUTHORIZE_DOT_NET_API_LOGIN_ID']
				@api_key	= args[:TRANSACTION_API_KEY] || ENV['AUTHORIZE_DOT_NET_TRANSACTION_API_KEY']
				@gateway	= ( args[:GATEWAY] || ENV['AUTHORIZE_DOT_NET_GATEWAY'] || :sandbox ).to_sym
			end

			def process( order, args = {} )
				self.calculate( order )
				return false if order.errors.present?

				profiles = get_customer_profile( order, credit_card: args[:credit_card] )
				return false if profiles == false

				anet_order = nil

				# create capture
				anet_transaction = AuthorizeNet::CIM::Transaction.new(@api_login, @api_key, :gateway => @gateway )
				amount = order.total / 100.0 # convert cents to dollars
		        response = anet_transaction.create_transaction_auth_capture( amount, profiles[:customer_profile_id], profiles[:payment_profile_id], anet_order )
				direct_response = response.direct_response


				# raise Exception.new("create auth capture error: #{response.message_text}") unless response.success?  # @todo remove


				# process response
				if response.success? && direct_response.success?

					# if capture is successful, save order, and create transaction.
					if order.save

						# update any subscriptions with profile ids
						order.order_items.each do |order_item|
							if order_item.subscription.present?
								order_item.subscription.provider = PROVIDER_NAME
								order_item.subscription.provider_customer_profile_reference = profiles[:customer_profile_id]
								order_item.subscription.provider_customer_payment_profile_reference = profiles[:payment_profile_id]
								order_item.subscription.save
							end
						end

						transaction = SwellEcom::Transaction.create( parent_obj: order, transaction_type: 'charge', reference_code: direct_response.transaction_id, customer_profile_reference: profiles[:customer_profile_id], customer_payment_profile_reference: profiles[:payment_profile_id], provider: PROVIDER_NAME, amount: order.total, currency: order.currency, status: 'approved' )

						raise Exception.new( "SwellEcom::Transaction create errors #{transaction.errors.full_messages}" ) if transaction.errors.present? # @todo remove

						return transaction

					end

				else

					puts response.xml

					orders.status = 'declined'

					transaction = false
					if orders.save
						transaction = Transaction.create( transaction_type: 'charge', reference_code: direct_response.try(:transaction_id), customer_profile_reference: profiles[:customer_profile_id], customer_payment_profile_reference: profiles[:payment_profile_id], provider: PROVIDER_NAME, amount: order.total, currency: order.currency, status: 'declined', message: response.message_text )
					end

					order.errors.add(:base, :processing_error, message: "Transaction declined.")

					return transaction
				end


				return false
			end

			def refund( args = {} )
				# assumes :amount, and :charge_transaction
				charge_transaction	= args.delete( :charge_transaction )
				parent				= args.delete( :order ) || args.delete( :parent )
				charge_transaction	||= Transaction.where( parent: parent ).charge.first if parent.present?
				anet_transaction_id = args.delete( :transaction_id )

				raise Exception.new( "charge_transaction must be an approved charge." ) unless charge_transaction.nil? || ( charge_transaction.charge? && charge_transaction.approved? )

				transaction = SwellEcom::Transaction.new( args )
				transaction.transaction_type	= 'refund'
				transaction.provider			= PROVIDER_NAME

				if charge_transaction.present?

					transaction.currency			||= charge_transaction.currency
					transaction.parent_obj			||= charge_transaction.parent_obj

					transaction.customer_profile_reference ||= charge_transaction.customer_profile_reference
					transaction.customer_payment_profile_reference ||= charge_transaction.customer_payment_profile_reference

					transaction.amount = charge_transaction.amount unless args[:amount].present?

					anet_transaction_id ||= charge_transaction.reference_code

				elsif anet_transaction_id.present?

					charge_transaction = SwellEcom::Transaction.charge.approved.find_by( provider: PROVIDER_NAME, reference_code: anet_transaction_id )

				end

				raise Exception.new('unable to find transaction') if anet_transaction_id.nil?

				# convert cents to dollars
				refund_dollar_amount = transaction.amount / 100.0

				anet_transaction = AuthorizeNet::CIM::Transaction.new(@api_login, @api_key, :gateway => @gateway )
				response = anet_transaction.create_transaction_refund(
					anet_transaction_id,
					refund_dollar_amount,
					transaction.customer_profile_reference,
					transaction.customer_payment_profile_reference
				)

				if response.message_code == CANNOT_REFUND_CHARGE
					# if you cannot refund it, that means the origonal charge
					# hasn't been settled yet, so you...

					if transaction.amount == charge_transaction.amount
						# have to void (but only if the refund is for the total amount)
						transaction.transaction_type = 'void'
						anet_transaction = AuthorizeNet::CIM::Transaction.new(@api_login, @api_key, :gateway => @gateway )
						response = anet_transaction.create_transaction_void(anet_transaction_id)

					else
						# OR create a refund that is unlinked to the transaction
						anet_transaction = AuthorizeNet::CIM::Transaction.new(@api_login, @api_key, :gateway => @gateway )
						# anet_transaction.set_fields(:trans_id => nil)
						anet_transaction.create_transaction(
							:refund,
							refund_dollar_amount,
							transaction.customer_profile_reference,
							transaction.customer_payment_profile_reference,
							nil, #order
							{}, #options
						)

						# response = anet_transaction.create_transaction_refund(
						# 	nil,
						# 	refund_dollar_amount,
						# 	transaction.customer_profile_reference,
						# 	transaction.customer_payment_profile_reference
						# )

					end
				end

				direct_response = response.direct_response

				# process response
				if response.success? && direct_response.success?

					transaction.status = 'approved'
					transaction.reference_code = direct_response.transaction_id

					# if capture is successful, create transaction.
					return transaction if transaction.save

					raise Exception.new( "SwellEcom::Transaction create errors #{transaction.errors.full_messages}" ) if transaction.errors.present? # @todo remove


				else
					puts response.xml # @todo remove

					transaction.status = 'declined'
					transaction.save
					raise Exception.new( "SwellEcom::Transaction create errors #{transaction.errors.full_messages}" ) if transaction.errors.present? # @todo remove

				end

				return false

			end

			protected

			def get_customer_profile( order, args = {} )
				anet_transaction = AuthorizeNet::CIM::Transaction.new(@api_login, @api_key, :gateway => @gateway )

				# find an existing customer profile
				subscriptions = order.order_items.select{ |order_item| order_item.item.is_a?( SwellEcom::Subscription ) && order_item.item == PROVIDER_NAME }.collect(&:item)
				return { customer_profile_id: subscriptions.first.provider_customer_profile_reference, payment_profile_id: subscriptions.first.provider_customer_payment_profile_reference } if subscriptions.present?

				raise Exception.new( 'cannot create payment profile without credit card info' ) unless args[:credit_card].present?

				billing_address_state = order.billing_address.state
				billing_address_state = order.billing_address.geo_state.try(:name) if billing_address_state.blank?
				billing_address_state = order.billing_address.geo_state.try(:abbrev) if billing_address_state.blank?

				anet_billing_address = AuthorizeNet::Address.new(
					:first_name		=> order.billing_address.first_name,
					:last_name		=> order.billing_address.last_name,
					# :company		=> nil,
					:street_address	=> "#{order.billing_address.street}\n#{order.billing_address.street2}".strip,
					:city			=> order.billing_address.city,
					:state			=> billing_address_state,
					:zip			=> order.billing_address.zip,
					:country		=> order.billing_address.geo_country.name,
					:phone			=> order.billing_address.phone,
				)

				credit_card = args[:credit_card]
				# @todo VALIDATE Credit card information

				anet_credit_card = AuthorizeNet::CreditCard.new(
					credit_card[:card_number].gsub(/\s/,''),
					credit_card[:expiration],
					card_code: credit_card[:card_code],
				)

				anet_payment_profile = AuthorizeNet::CIM::PaymentProfile.new(
					:payment_method		=> anet_credit_card,
					:billing_address	=> anet_billing_address,
				)

				anet_customer_profile = AuthorizeNet::CIM::CustomerProfile.new(
					:email			=> order.user.email,
					:id				=> order.user.id,
					:phone			=> order.billing_address.phone,
					:address		=> anet_billing_address,
					:description	=> "#{anet_billing_address.first_name} #{anet_billing_address.last_name}"
				)
				anet_customer_profile.payment_profiles = anet_payment_profile


				# create a new customer profile
				response = anet_transaction.create_profile( anet_customer_profile )

				# recover a customer profile if it already exists.
				if response.message_code == ERROR_DUPLICATE_CUSTOMER_PROFILE
					anet_transaction = AuthorizeNet::CIM::Transaction.new(@api_login, @api_key, :gateway => @gateway )

					profile_id = response.message_text.match( /(\d{4,})/)[1]

					response = anet_transaction.get_profile( profile_id.to_s )
					customer_profile_id = response.profile_id
					customer_payment_profile_id = response.profile.payment_profiles.first.try(:customer_payment_profile_id)

					return { customer_profile_id: customer_profile_id, payment_profile_id: customer_payment_profile_id }

				elsif response.success?

					customer_payment_profile_id = response.payment_profile_ids.last

					return { customer_profile_id: response.profile_id, payment_profile_id: customer_payment_profile_id }

				else

					puts response.xml

					if response.message_code == ERROR_INVALID_PAYMENT_PROFILE
						order.errors.add(:base, :processing_error, message: 'Invalid Payment Information')
					else
						order.errors.add(:base, :processing_error, message: 'Unable to create customer profile')
					end

				end

				return false
			end

		end

	end

end
