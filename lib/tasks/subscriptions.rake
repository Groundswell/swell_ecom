# desc "Explaining what the task does"
namespace :swell_ecom do

	task payment_profile_expiration_reminder: :environment do

		subscriptions = SwellEcom::InternalSubscription.active
		subscriptions = subscriptions.where( payment_profile_expires_at: Time.now..1.month.from_now ).where.not( payment_profile_expires_at: nil )

		subscriptions.find_each do |subscription|

			if subscription.properties['payment_profile_expiration_reminder'].nil?

				subscription.properties = subscription.properties.merge( 'payment_profile_expiration_reminder' => Time.now.to_i )
				subscription.save

				SwellEcom::SubscriptionMailer.payment_profile_expiration_reminder( subscription ).deliver_now

			end

		end

	end

	task process_subscriptions: :environment do

		time_now = Time.now
		subscription_service = SwellEcom.subscription_service_class.constantize.new( SwellEcom.subscription_service_config )

		SwellEcom::InternalSubscription.ready_for_next_charge( time_now ).find_each do |subscription|

			begin

				order = subscription_service.charge_subscription( subscription, now: time_now )

				if subscription.failed?
					SwellEcom::SubscriptionMailer.renewal_failure( subscription ).deliver_now
				elsif order.errors.blank?
					SwellEcom::OrderMailer.receipt( order ).deliver_now
				end

			rescue Exception => e

				puts "Exception: #{e.message}"
				NewRelic::Agent.notice_error(e) if defined?( NewRelic )

			end

		end

	end

end
