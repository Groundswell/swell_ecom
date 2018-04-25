module SwellEcom
	class SubscriptionPlan < ApplicationRecord
		self.table_name = 'subscription_plans'

		include SwellMedia::Concerns::URLConcern
		include SwellMedia::Concerns::AvatarAsset
		#include SwellMedia::Concerns::ExpiresCache
		include SwellEcom::Concerns::MoneyAttributesConcern

		enum status: { 'draft' => 0, 'active' => 1, 'archive' => 2, 'trash' => 3 }
		enum availability: { 'backorder' => -1, 'pre_order' => 0, 'open_availability' => 1 }
		enum package_shape: { 'no_shape' => 0, 'letter' => 1, 'box' => 2, 'cylinder' => 3 }

		belongs_to 	:item, polymorphic: true, required: false

		validates		:title, presence: true, unless: :allow_blank_title?

		validates	:billing_interval_value, presence: true, allow_blank: false
		validates_numericality_of :billing_interval_value, greater_than_or_equal_to: 1
		validates	:billing_interval_unit, presence: true, allow_blank: false
		validates_inclusion_of :billing_interval_unit, :in => %w(month months day days week weeks year years), :allow_nil => false, message: '%{value} is not a valid unit of time.'


		validates	:trial_interval_value, presence: true, allow_blank: false
		validates_numericality_of :trial_interval_value, greater_than_or_equal_to: 1
		validates	:trial_interval_unit, presence: true, allow_blank: false
		validates_inclusion_of :trial_interval_unit, :in => %w(month months day days week weeks year years), :allow_nil => false, message: '%{value} is not a valid unit of time.'

		money_attributes :trial_price, :price, :shipping_price

		mounted_at '/subscriptions'

		after_create :on_create
		after_update :on_update
		before_save	:set_publish_at

		attr_accessor	:slug_pref

		include FriendlyId
		friendly_id :slugger, use: [ :slugged, :history ]

		def self.published( args = {} )
			where( "subscription_plans.publish_at <= :now", now: Time.zone.now ).active
		end

		def swell_ecom_uid
			"subscription_plan_#{self.id}"
		end

		def page_event_data
			category_name = self.product_category.name if self.respond_to?(:product_category)

			event_price = self.price_as_money
			event_price = self.trial_price_as_money if self.trial?

			data = {
				id: swell_ecom_uid,
				name: self.title,
				price: event_price,
				category: category_name,
			}

			data
		end

		def page_meta
			if self.title.present?
				title = "#{self.title} )°( #{SwellMedia.app_name}"
			else
				title = SwellMedia.app_name
			end

			return {
				page_title: title,
				title: self.title,
				description: self.sanitized_description,
				image: self.avatar,
				url: self.url,
				twitter_format: 'summary_large_image',
				type: 'Product',
				og: {
					"article:published_time" => self.publish_at.iso8601,
					"product:price:amount" => self.price / 100.to_f,
					"product:price:currency" => 'USD'
				},
				data: {
					'url' => self.url,
					'name' => self.title,
					'description' => self.sanitized_description,
					'datePublished' => self.publish_at.iso8601,
					'image' => self.avatar
				}

			}
		end

		def published?
			active? && publish_at < Time.zone.now
		end

		def sanitized_content
			ActionView::Base.full_sanitizer.sanitize( self.content )
		end

		def sanitized_description
			ActionView::Base.full_sanitizer.sanitize( self.description )
		end

		def slugger
			if self.slug_pref.present?
				self.slug = nil # friendly_id 5.0 only updates slug if slug field is nil
				return self.slug_pref
			else
				return self.title
			end
		end

		def sku
			"sub-#{self.slug}"
		end

		def tags_csv
			self.tags.join(',')
		end

		def tags_csv=(tags_csv)
			self.tags = tags_csv.split(/,\s*/)
		end

		def trial?
			self.trial_max_intervals > 0
		end


		private
			def allow_blank_title?
				self.slug_pref.present?
			end

			def set_publish_at
				# set publish_at
				self.publish_at ||= Time.zone.now
			end

			def on_create
				if defined?( Elasticsearch::Model )
					__elasticsearch__.index_document
				end
			end

			def on_update
			 	if defined?( Elasticsearch::Model )
					__elasticsearch__.index_document rescue Product.first.__elasticsearch__.update_document
				end
			end

	end
end
