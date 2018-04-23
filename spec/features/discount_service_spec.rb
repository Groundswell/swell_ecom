require "spec_helper"

describe "SubscriptionService" do

	let(:user) { ::User.create( email: "#{(0...20).map { (65 + rand(26)).chr }.join}@groundswellent.com", first_name: 'Michael', last_name: (0...8).map { (65 + rand(26)).chr }.join ) }
	let(:address) { SwellEcom::GeoAddress.new( first_name: 'Michael', last_name: (0...8).map { (65 + rand(26)).chr }.join, zip: '92126', street: '123 Test st', phone: "1#{(0...10).map { (rand(8)+1).to_s }.join}", city: 'San Diego', geo_country: SwellEcom::GeoCountry.new( name: 'United States', abbrev: 'US' ), geo_state: SwellEcom::GeoState.new( name: 'California', abbrev: 'CA' ) ) }
	let(:new_order) {

		subscription_plan = SwellEcom.default_subscription_class.constantize.new( title: 'Test Trial Subscription Plan', trial_price: 99, trial_max_intervals: 2, price: 12900, billing_interval_unit: 'weeks', billing_interval_value: 4, trial_interval_unit: 'days', trial_interval_value: 7 )
		subscription = SwellEcom.default_subscription_class.constantize.new( subscription_plan: subscription_plan, user: user, billing_address: address, shipping_address: address, quantity: 1, status: 'active', next_charged_at: Time.now, current_period_start_at: 1.week.ago, current_period_end_at: Time.now, provider: 'Authorize.net' )

		order = SwellEcom::Order.new( billing_address: subscription.billing_address, shipping_address: subscription.shipping_address, user: subscription.user )
		order.order_items.new item: subscription_plan, subscription: subscription, price: subscription_plan.trial_price, subtotal: subscription_plan.trial_price, order_item_type: 'prod', quantity: 1, title: subscription_plan.title, tax_code: subscription_plan.tax_code

		order
	}

	before :all do
		@discount_service = SwellEcom::DiscountService.new
	end

	it "should be able to calculate fixed discount" do

		discount = SwellEcom::Discount.new( start_at: Time.now, status: 'active' )
		discount.discount_items.new( discount_amount: 100, discount_type: 'fixed' )

		discount_order_item = new_order.order_items.new( item: discount, order_item_type: 'discount' )

		@discount_service.calculate( new_order, pre_tax: true )

		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -100

		@discount_service.calculate( new_order )

		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -100

	end

	it "should be able to calculate fixed_each" do
		product = SwellEcom::Product.new
		product_order_item = new_order.order_items.new( subtotal: 14900, order_item_type: 'prod', item: product, quantity: 2 )

		discount = SwellEcom::Discount.new( start_at: Time.now, status: 'active' )
		discount.discount_items.new( discount_amount: 100, discount_type: 'fixed_each', order_item_type: 'prod' )

		discount_order_item = new_order.order_items.new( item: discount, order_item_type: 'discount' )

		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -300

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -300

		product_order_item.quantity = 4
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -500

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -500


	end

	it "should be able to calculate percent discount" do

		discount = SwellEcom::Discount.new( start_at: Time.now, status: 'active' )
		discount_item = discount.discount_items.new( discount_amount: 100, discount_type: 'percent', order_item_type: nil )

		discount_order_item = new_order.order_items.new( item: discount, order_item_type: 'discount' )

		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -99

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -99


		#add shipping
		shipping_order_item = new_order.order_items.new( subtotal: 495, order_item_type: 'shipping' )
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -594

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -594

		#80 percent
		discount_item.discount_amount = 80
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -475

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -475

		#35 percent
		discount_item.discount_amount = 35
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -208

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -208


	end

	it "should be able to calculate mixed fixed and percent discount" do
		shipping_order_item = new_order.order_items.new( subtotal: 495, order_item_type: 'shipping' )

		discount = SwellEcom::Discount.new( start_at: Time.now, status: 'active' )

		percent_discount_item = discount.discount_items.new( discount_amount: 35, discount_type: 'percent', order_item_type: nil )
		fixed_discount_item = discount.discount_items.new( discount_amount: 10, discount_type: 'fixed', order_item_type: nil )

		discount_order_item = new_order.order_items.new( item: discount, order_item_type: 'discount' )

		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -218

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -218


		percent_discount_item.order_item_type = 'prod'
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -45

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -45


		percent_discount_item.order_item_type = 'shipping'
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -183

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -183

	end

	it "should be able to calculate discount for specific products/plans" do
		product = SwellEcom::Product.new

		discount = SwellEcom::Discount.new( start_at: Time.now, status: 'active' )
		percent_discount_item = discount.discount_items.new( discount_amount: 50, discount_type: 'percent', order_item_type: 'prod', applies_to: product )

		product_order_item = new_order.order_items.new( subtotal: 14900, order_item_type: 'prod', item: product )
		discount_order_item = new_order.order_items.new( item: discount, order_item_type: 'discount' )


		# a product
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -7450

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -7450


		# a subscription
		percent_discount_item.applies_to = new_order.order_items.first.item
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -50

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -50

	end

	it "should be able to calculate fixed discount with minimum taxes" do

		discount = SwellEcom::Discount.new( start_at: Time.now, status: 'active', minimum_tax_subtotal: 10 )
		discount.discount_items.new( discount_amount: 100, discount_type: 'fixed' )

		discount_order_item = new_order.order_items.new( item: discount, order_item_type: 'discount' )
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq 0

		tax_order_item = new_order.order_items.new( subtotal: 10, order_item_type: 'tax' )
		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -100

		tax_order_item.subtotal = 1
		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '["Does not meet minimum tax requirement"]'
		expect(discount_order_item.subtotal).to eq 0

	end

	it "should be able to calculate fixed discount with minimum prod" do

		discount = SwellEcom::Discount.new( start_at: Time.now, status: 'active', minimum_prod_subtotal: 90 )
		discount.discount_items.new( discount_amount: 100, discount_type: 'fixed' )

		discount_order_item = new_order.order_items.new( item: discount, order_item_type: 'discount' )
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -100

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -100

		discount.minimum_prod_subtotal = 100
		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '["Does not meet minimum purchase requirement"]'
		expect(discount_order_item.subtotal).to eq 0

	end

	it "should be able to calculate fixed discount with minimum shipping" do

		discount = SwellEcom::Discount.new( start_at: Time.now, status: 'active', minimum_shipping_subtotal: 100 )
		discount.discount_items.new( discount_amount: 100, discount_type: 'fixed' )

		shipping_order_item = new_order.order_items.new( subtotal: 495, order_item_type: 'shipping' )

		discount_order_item = new_order.order_items.new( item: discount, order_item_type: 'discount' )
		@discount_service.calculate( new_order, pre_tax: true )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -100

		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '[]'
		expect(discount_order_item.subtotal).to eq -100

		shipping_order_item.subtotal = 99
		@discount_service.calculate( new_order )
		expect(new_order.errors.full_messages.to_s).to eq '["Does not meet minimum shipping requirement"]'
		expect(discount_order_item.subtotal).to eq 0

	end

end
