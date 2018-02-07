module SwellEcom
  module PayPalCheckoutHelper

	  def paypal_script( args = {} )
		  transaction_service = args[:transaction_service]
		  button_selector = args[:button_selector]
		  button_selector ||= '#paypal_checkout_button'
		  checkout_form_id = args[:form_id] || '#checkout_form'

		  content_tag(:script, src: 'https://www.paypalobjects.com/api/checkout.js' )
		  content_tag(:script) do
			  <<-HTML
paypal.Button.render({

	env: '#{transaction_service.environment}', // sandbox | production

	// Show the buyer a 'Pay Now' button in the checkout flow
	commit: true,

	// payment() is called when the button is clicked
	payment: function() {
		console.log('payment')

		// Set up a url on your server to create the payment
		var CREATE_URL = '#{swell_ecom.new_paypal_checkout_url()}';
		var payment_data = $('#{checkout_form_id}').serializeArray()
		// Make a call to your server to set up the payment
		return paypal.request.post(CREATE_URL, payment_data)
			.then(function(res) {
				if( res.status == 'success' ) {
					return res.payment_id;
				} else {
					// @todo display error message
					return false
				}
			});
	},

	// onAuthorize() is called when the buyer approves the payment
	onAuthorize: function(data, actions) {
		console.log('onAuthorize',data, actions)

		// Set up a url on your server to execute the payment
		var EXECUTE_URL = '#{swell_ecom.paypal_checkout_url()}';

		// Set up the data you need to pass to your server
		var execute_data = {
			paymentID: data.paymentID,
			payerID: data.payerID
		};

		console.log(EXECUTE_URL,execute_data)

		// Make a call to your server to execute the payment
		return paypal.request.post(EXECUTE_URL, execute_data)
			.then(function (res) {
				console.log('Payment Complete!')
			});
	}

}, '#{button_selector}');
HTML
		  end
	  end

  end
end
