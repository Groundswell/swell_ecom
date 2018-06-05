module SwellEcom
	class Subscription < ApplicationRecord
		self.table_name = 'subscriptions'

		include SwellEcom::Concerns::MoneyAttributesConcern

		enum status: { 'on_hold' => -2, 'canceled' => -1, 'failed' => 0, 'active' => 1 }

		belongs_to :user
		belongs_to :subscription_plan
		belongs_to :discount, required: false
		belongs_to :shipping_carrier_service, required: false

		belongs_to 	:billing_address, class_name: 'GeoAddress'
		belongs_to 	:shipping_address, class_name: 'GeoAddress'

		before_create :generate_order_code
		before_create :initialize_timestamps
		before_save :update_timestamps

		accepts_nested_attributes_for :billing_address, :shipping_address, :user

		money_attributes :amount, :trial_amount, :price, :trial_price

		validates	:amount, presence: true, allow_blank: false
		validates	:price, presence: true, allow_blank: false
		validates	:trial_amount, presence: true, allow_blank: false
		validates	:trial_price, presence: true, allow_blank: false
		validates_numericality_of :quantity, greater_than_or_equal_to: 1
		validates_numericality_of :amount, greater_than_or_equal_to: 0
		validates_numericality_of :price, greater_than_or_equal_to: 0
		validates_numericality_of :trial_amount, greater_than_or_equal_to: 0
		validates_numericality_of :trial_price, greater_than_or_equal_to: 0

		validates	:billing_interval_value, presence: true, allow_blank: false
		validates_numericality_of :billing_interval_value, greater_than_or_equal_to: 1
		validates	:billing_interval_unit, presence: true, allow_blank: false
		validates_inclusion_of :billing_interval_unit, :in => %w(month months day days week weeks year years), :allow_nil => false, message: '%{value} is not a valid unit of time.'

		def avatar
			self.subscription_plan.avatar
		end

		def self.ready_for_next_charge( time_now = nil )
			time_now ||= Time.now
			active.where( 'next_charged_at < :now', now: time_now )
		end

		def is_next_interval_a_trial?
			return false unless self.subscription_plan.trial?

			if not( self.persisted? )
				return true
			else
				interval_count = SwellEcom::OrderItem.where( item: self ).count + SwellEcom::OrderItem.where( subscription: self ).count
				return interval_count < self.subscription_plan.trial_max_intervals
			end
		end

		def order
			Order.joins(:order_items).where( order_items: { subscription_id: self.id } ).first
		end

		def orders
			if self.order.present?
				Order.where( "orders.id = :order_id OR (orders.parent_type = :subscription_type AND orders.parent_id = :subscription_id)", subscription_id: self.id, subscription_type: SwellEcom::Subscription.base_class.name, order_id: self.order.id )
			else
				Order.where( parent: self )
			end
		end

		def page_event_data
			self.subscription_plan.page_event_data
		end

		def ready_for_next_charge?( time_now = nil )
			time_now ||= Time.now
			self.active? && self.next_charged_at < time_now
		end

		def sku
			subscription_plan.sku
		end

		def title
			subscription_plan.title
		end

		def to_s
			"#{self.title} (#{self.code})"
		end

		def url
			self.subscription_plan.url
		end

		private

		def generate_order_code
			self.code = loop do
  				token = SecureRandom.urlsafe_base64( 6 ).downcase.gsub(/_/,'-')
				token = "#{SwellEcom.subscription_code_prefix}#{token}"if SwellEcom.order_code_prefix.present?
				token = "#{token}#{SwellEcom.subscription_code_postfix}"if SwellEcom.order_code_postfix.present?
  				break token unless Subscription.exists?( code: token )
			end
		end

		def initialize_timestamps
			# Fill in any timestamp blanks

			if self.subscription_plan.present?

				self.start_at ||= self.created_at
				self.current_period_start_at ||= self.start_at

				trial_interval = self.subscription_plan.trial_interval_value.try( self.subscription_plan.trial_interval_unit )
				billing_interval = self.subscription_plan.billing_interval_value.try( self.subscription_plan.billing_interval_unit )

				if self.subscription_plan.trial?

					self.trial_start_at ||= self.start_at
					self.trial_end_at ||= self.trial_start_at + trial_interval * self.subscription_plan.trial_max_intervals

					self.current_period_end_at ||= self.current_period_start_at + trial_interval
				end
				self.current_period_end_at ||= self.current_period_start_at + billing_interval

				self.next_charged_at ||= self.current_period_end_at

			end
		end

		def update_timestamps
			self.canceled_at = Time.now if not( self.canceled_at_changed? ) && self.status_changed? && self.canceled?
		end

	end
end
