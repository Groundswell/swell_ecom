module SwellEcom
	class SubscriptionPlan < ActiveRecord::Base

		self.table_name = 'subscription_plans'

		if defined?( Elasticsearch::Model )

			include Elasticsearch::Model

			settings index: { number_of_shards: 1 } do
				mappings dynamic: 'false' do
					indexes :id, type: 'integer'
					indexes :category_id, type: 'integer'
					indexes :category_name, analyzer: 'english', index_options: 'offsets'
					indexes :raw_category_name, index: :not_analyzed
					indexes :slug, index: :not_analyzed
					indexes :created_at, type: 'date'
					indexes :title, analyzer: 'english', index_options: 'offsets'
					indexes :title_downcase_raw, type: :string, index: :not_analyzed
					indexes :description, analyzer: 'english', index_options: 'offsets'
					indexes :published?, type: 'boolean'

					indexes :tags, type: 'nested' do
						indexes :name, analyzer: 'english', index_options: 'offsets'
						indexes :raw_name, index: :not_analyzed
						indexes :name_downcase, analyzer: 'english', index_options: 'offsets'
						indexes :raw_name_downcase, index: :not_analyzed
					end
				end
			end

		end

		enum status: { 'draft' => 0, 'active' => 1, 'archive' => 2, 'trash' => 3 }

		validates		:title, presence: true, unless: :allow_blank_title?

		attr_accessor	:category_name

		include SwellMedia::Concerns::URLConcern
		include SwellMedia::Concerns::AvatarAsset
		#include SwellMedia::Concerns::ExpiresCache

		mounted_at '/subscriptions'

		belongs_to 	:product_category, foreign_key: :category_id

		after_create :on_create
		after_update :on_update
		before_save	:set_publish_at

		attr_accessor	:slug_pref

		include FriendlyId
		friendly_id :slugger, use: [ :slugged, :history ]

		acts_as_taggable_array_on :tags


		def self.published( args = {} )
			where( "subscription_plans.publish_at <= :now", now: Time.zone.now ).active
		end

		def page_event_data
			{
				id: self.id,
				name: self.title,
				price: self.price / 100.0,
				brand: (self.brand || ''),
				category: self.product_category.try(:name),
				variant: '',
			}
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

		def tags_csv
			self.tags.join(',')
		end

		def tags_csv=(tags_csv)
			self.tags = tags_csv.split(/,\s*/)
		end

		def as_indexed_json(options={})
			{
				id:					self.id,
				category_id:		self.category_id,
				category_name:		self.product_category.try( :name ),
				raw_category_name:	self.product_category.try( :name ),
				slug:				self.slug,
				created_at:			self.created_at,
				title: 				self.title,
				title_downcase_raw: self.title.try(:downcase),
				description:		self.description,
				published?:			self.published?,
				tags:				self.tags.collect{ |tag| { name: tag, raw_name: tag, name_downcase: tag.downcase, raw_name_downcase: tag.downcase } },
			}.as_json
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
