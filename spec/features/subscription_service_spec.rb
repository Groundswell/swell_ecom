require "spec_helper"

describe "SubscriptionService" do

	let(:user) { ::User.create( email: "#{(0...20).map { (65 + rand(26)).chr }.join}@groundswellent.com", first_name: 'Michael', last_name: (0...8).map { (65 + rand(26)).chr }.join ) }
	let(:address) { SwellEcom::GeoAddress.new( first_name: 'Michael', last_name: (0...8).map { (65 + rand(26)).chr }.join, zip: '92126', street: '123 Test st', phone: "1#{(0...10).map { (rand(8)+1).to_s }.join}", city: 'San Diego', geo_country: SwellEcom::GeoCountry.new( name: 'United States', abbrev: 'US' ), geo_state: SwellEcom::GeoState.new( name: 'California', abbrev: 'CA' ) ) }
	let(:credit_card) { { card_number: '4111111111111111', expiration: '12/'+(Time.now + 1.year).strftime('%y'), card_code: '1234' } }
	let(:new_trial2_subscription) {

		subscription_plan = SwellEcom::SubscriptionPlan.new( title: 'Test Trial Subscription Plan', trial_price: 99, trial_max_intervals: 2, price: 12900, billing_interval_unit: 'weeks', billing_interval_value: 4, trial_interval_unit: 'days', trial_interval_value: 7 )
		subscription = SwellEcom.default_subscription_class.constantize.new( subscription_plan: subscription_plan, user: user, billing_address: address, shipping_address: address, quantity: 1, status: 'active', next_charged_at: Time.now, current_period_start_at: 1.week.ago, current_period_end_at: Time.now, provider: 'Authorize.net' )

		order = SwellEcom::Order.new( billing_address: subscription.billing_address, shipping_address: subscription.shipping_address, user: subscription.user )
		order.order_items.new item: subscription_plan, subscription: subscription, price: subscription_plan.trial_price, subtotal: subscription_plan.trial_price, order_item_type: 'prod', quantity: 1, title: subscription_plan.title, tax_code: subscription_plan.tax_code
		@transaction_service.process( order, credit_card: credit_card )

		subscription
	}
	let(:new_trial1_subscription) {

		subscription_plan = SwellEcom::SubscriptionPlan.new( title: 'Test Trial Subscription Plan', trial_price: 99, trial_max_intervals: 1, price: 12900, billing_interval_unit: 'weeks', billing_interval_value: 4, trial_interval_unit: 'days', trial_interval_value: 7 )
		subscription = SwellEcom.default_subscription_class.constantize.new( subscription_plan: subscription_plan, user: user, billing_address: address, shipping_address: address, quantity: 1, status: 'active', next_charged_at: Time.now, current_period_start_at: 1.week.ago, current_period_end_at: Time.now, provider: 'Authorize.net' )

		order = SwellEcom::Order.new( billing_address: subscription.billing_address, shipping_address: subscription.shipping_address, user: subscription.user )
		order.order_items.new item: subscription_plan, subscription: subscription, price: subscription_plan.trial_price, subtotal: subscription_plan.trial_price, order_item_type: 'prod', quantity: 1, title: subscription_plan.title, tax_code: subscription_plan.tax_code
		@transaction_service.process( order, credit_card: credit_card )

		subscription
	}

	before :all do
		@api_login	= ENV['AUTHORIZE_DOT_NET_API_LOGIN_ID']
		@api_key	= ENV['AUTHORIZE_DOT_NET_TRANSACTION_API_KEY']
		@gateway	= :sandbox

		@transaction_service = SwellEcom::TransactionServices::AuthorizeDotNetTransactionService.new( API_LOGIN_ID: @api_login, TRANSACTION_API_KEY: @api_key, GATEWAY: @gateway )
		@tax_service = SwellEcom::TaxService.new
		@shipping_service = SwellEcom::ShippingService.new
	end

	it "should support instantiation" do

		subscription_service = SwellEcom.subscription_service_class.constantize.new( SwellEcom.subscription_service_config.merge( transaction_service: @transaction_service, tax_service: @tax_service, shipping_service: @shipping_service ) )
		subscription_service.should be_instance_of(SwellEcom::SubscriptionService)

	end

	it "subscription is ready" do

		subscription = SwellEcom::Subscription.create( next_charged_at: 1.minute.ago, status: 'active' )
		expect(subscription.ready_for_next_charge?).to eq true
		expect(SwellEcom::Subscription.where( id: subscription.id ).ready_for_next_charge.count).to eq 1

		subscription = SwellEcom::Subscription.create( next_charged_at: 1.minute.from_now, status: 'active' )
		expect(subscription.ready_for_next_charge?).to eq false
		expect(SwellEcom::Subscription.where( id: subscription.id ).ready_for_next_charge.count).to eq 0

		subscription = SwellEcom::Subscription.create( next_charged_at: 1.minute.ago, status: 'canceled' )
		expect(subscription.ready_for_next_charge?).to eq false
		expect(SwellEcom::Subscription.where( id: subscription.id ).ready_for_next_charge.count).to eq 0

		subscription = SwellEcom::Subscription.create( next_charged_at: 1.minute.ago, status: 'failed' )
		expect(subscription.ready_for_next_charge?).to eq false
		expect(SwellEcom::Subscription.where( id: subscription.id ).ready_for_next_charge.count).to eq 0

		subscription = SwellEcom::Subscription.create( next_charged_at: 1.minute.from_now, status: 'canceled' )
		expect(subscription.ready_for_next_charge?).to eq false
		expect(SwellEcom::Subscription.where( id: subscription.id ).ready_for_next_charge.count).to eq 0

		subscription = SwellEcom::Subscription.create( next_charged_at: 1.minute.from_now, status: 'failed' )
		expect(subscription.ready_for_next_charge?).to eq false
		expect(SwellEcom::Subscription.where( id: subscription.id ).ready_for_next_charge.count).to eq 0

	end

	it "subscription is in a trial interval" do

		subscription = SwellEcom.default_subscription_class.constantize.new( subscription_plan: SwellEcom::SubscriptionPlan.new( trial_max_intervals: 0 ) )
		expect(subscription.is_next_interval_a_trial?).to eq false

		subscription = SwellEcom.default_subscription_class.constantize.new( subscription_plan: SwellEcom::SubscriptionPlan.new( trial_max_intervals: 1 ) )
		expect(subscription.is_next_interval_a_trial?).to eq true

		subscription = SwellEcom.default_subscription_class.constantize.new( subscription_plan: SwellEcom::SubscriptionPlan.new( trial_max_intervals: 2 ) )
		expect(subscription.is_next_interval_a_trial?).to eq true

		subscription = SwellEcom.default_subscription_class.constantize.new( subscription_plan: SwellEcom::SubscriptionPlan.new( trial_max_intervals: 1 ) )
		subscription.save
		SwellEcom::OrderItem.create( subscription: subscription )
		expect(subscription.is_next_interval_a_trial?).to eq false

		subscription = SwellEcom.default_subscription_class.constantize.new( subscription_plan: SwellEcom::SubscriptionPlan.new( trial_max_intervals: 2 ) )
		subscription.save
		SwellEcom::OrderItem.create( subscription: subscription )
		expect(subscription.is_next_interval_a_trial?).to eq true
		SwellEcom::OrderItem.create( item: subscription )
		expect(subscription.is_next_interval_a_trial?).to eq false


	end

	it "should charge an active subscription with active trial" do

		subscription = new_trial2_subscription

		last_current_period_start_at	= subscription.current_period_start_at
		last_current_period_end_at		= subscription.current_period_end_at
		last_next_charged_at			= subscription.next_charged_at

		sleep 2.25.minutes # sleep 2 minutes to get over the duplicate window

		subscription_service = SwellEcom.subscription_service_class.constantize.new( SwellEcom.subscription_service_config.merge( transaction_service: @transaction_service, tax_service: @tax_service, shipping_service: @shipping_service ) )

		order = subscription_service.charge_subscription( subscription )

		order.should be_instance_of(SwellEcom::Order)
		expect(order.payment_status).to eq 'paid'
		expect(order.fulfillment_status).to eq 'unfulfilled'
		expect(order.generated_by).to eq 'system_generaged'
		expect(order.total).to eq 99
		expect(order.parent).to eq subscription
		expect(order.billing_address).to eq subscription.billing_address
		expect(order.shipping_address).to eq subscription.shipping_address
		expect(order.user).to eq subscription.user
		expect(order.email).to eq subscription.user.email
		expect(order.currency).to eq subscription.currency
		expect(order.order_items.prod.count).to eq 1

		order.order_items.prod.each do |order_item|
			expect(order_item.item).to eq subscription
			expect(order_item.subtotal).to eq 99
		end

		expect(order.transactions.count).to eq 1
		expect(order.transactions.approved.count).to eq 1

		expect( subscription.current_period_start_at - last_current_period_start_at ).to eq 1.week
		expect( subscription.current_period_end_at - last_current_period_end_at ).to eq 1.week
		expect( subscription.next_charged_at - last_next_charged_at ).to eq 1.week

	end


	it "should charge an active subscription with inactive trial" do

		subscription = new_trial1_subscription

		last_current_period_start_at	= subscription.current_period_start_at
		last_current_period_end_at		= subscription.current_period_end_at
		last_next_charged_at			= subscription.next_charged_at

		sleep 2.25.minutes # sleep 2 minutes to get over the duplicate window

		subscription_service = SwellEcom.subscription_service_class.constantize.new( SwellEcom.subscription_service_config.merge( transaction_service: @transaction_service, tax_service: @tax_service, shipping_service: @shipping_service ) )

		order = subscription_service.charge_subscription( subscription )

		order.should be_instance_of(SwellEcom::Order)
		expect(order.payment_status).to eq 'paid'
		expect(order.fulfillment_status).to eq 'unfulfilled'
		expect(order.generated_by).to eq 'system_generaged'
		expect(order.total).to eq 12900
		expect(order.parent).to eq subscription
		expect(order.billing_address).to eq subscription.billing_address
		expect(order.shipping_address).to eq subscription.shipping_address
		expect(order.user).to eq subscription.user
		expect(order.email).to eq subscription.user.email
		expect(order.currency).to eq subscription.currency
		expect(order.order_items.prod.count).to eq 1

		order.order_items.prod.each do |order_item|
			expect(order_item.item).to eq subscription
			expect(order_item.subtotal).to eq 12900
		end

		expect(order.transactions.count).to eq 1
		expect(order.transactions.approved.count).to eq 1

		expect( subscription.current_period_start_at - last_current_period_start_at ).to eq 4.weeks
		expect( subscription.current_period_end_at - last_current_period_end_at ).to eq 4.weeks
		expect( subscription.next_charged_at - last_next_charged_at ).to eq 4.weeks

	end


	it "should not charge inactive" do

		subscription_service = SwellEcom.subscription_service_class.constantize.new( SwellEcom.subscription_service_config.merge( transaction_service: @transaction_service, tax_service: @tax_service, shipping_service: @shipping_service ) )
		subscription = new_trial1_subscription

		subscription.status = 'canceled'
		expect{ order = subscription_service.charge_subscription( subscription ) }.to raise_error("Subscription #{subscription.id} isn't active, so can't be charged.")


		subscription.status = 'failed'
		expect{ order = subscription_service.charge_subscription( subscription ) }.to raise_error("Subscription #{subscription.id} isn't active, so can't be charged.")

		subscription.status = 'active'
		order = subscription_service.charge_subscription( subscription )
		order.should be_instance_of(SwellEcom::Order)

	end


	it "should not charge if subscription is not yet past next_charged_at" do

		subscription_service = SwellEcom.subscription_service_class.constantize.new( SwellEcom.subscription_service_config.merge( transaction_service: @transaction_service, tax_service: @tax_service, shipping_service: @shipping_service ) )
		subscription = new_trial1_subscription
		time_now = Time.now

		subscription.next_charged_at = time_now + 10.minutes
		expect{ order = subscription_service.charge_subscription( subscription, now: time_now ) }.to raise_error("Subscription #{subscription.id} isn't ready to renew yet.  Currently it's #{time_now}, but subscription doesn't renew until #{subscription.next_charged_at}")

	end

	it "should handle expired credit cards" do

		subscription_service = SwellEcom.subscription_service_class.constantize.new( SwellEcom.subscription_service_config.merge( transaction_service: @transaction_service, tax_service: @tax_service, shipping_service: @shipping_service ) )
		subscription = new_trial1_subscription
		time_now = Time.now + 2.years

		expect( subscription.status ).to eq 'active'
		order = subscription_service.charge_subscription( subscription )
		expect( subscription.status ).to eq 'failed'

		order.should be_instance_of(SwellEcom::Order)
		expect(order.payment_status).to eq 'declined'
		expect(order.fulfillment_status).to eq 'unfulfilled'
		expect( order.errors.present? ).to eq true
		expect( order.errors.to_json ).to eq ''

	end

end
