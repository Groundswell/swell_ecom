# desc "Explaining what the task does"
namespace :swell_ecom do

	task cached_discount_stats_backfill: :environment do

    # a list of all discounts used in active orders.
    discount_order_items = SwellEcom::OrderItem.discount.joins( :order ).merge( SwellEcom::Order.active )

    SwellEcom::Discount.all.find_each do |discount|

      discount.cached_uses = discount_order_items.where( item: discount ).count
      discount.save

    end

	end

	task cached_discount_stats_update: :environment do

    date_range = 1.day.ago..Time.now

    # a list of all discounts used in active orders.
    discount_order_items = SwellEcom::OrderItem.discount.joins( :order ).merge( SwellEcom::Order.active )

    updated_discounts_ids = discount_order_items.where( created_at: date_range ).select(:item_id)

    SwellEcom::Discount.where( id: updated_discounts_ids ).find_each do |discount|

      discount.cached_uses = discount_order_items.where( item: discount ).count
      discount.save

    end

	end

end
