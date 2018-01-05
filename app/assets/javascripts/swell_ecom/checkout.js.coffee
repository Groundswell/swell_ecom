#= require ./plugins/jquery.payment
#= require ./plugins/jquery.card
#= require ./plugins/validator.js
#= require ./custom/stripe_integration.js
#= require ./plugins/jquery.caret.js
#= require ./plugins/jquery.mobilePhoneNumber.js

$ ->

	$.fn.validator.Constructor.INPUT_SELECTOR = '.collapse.collapse-ignore.in '+$.fn.validator.Constructor.INPUT_SELECTOR+', '+$.fn.validator.Constructor.INPUT_SELECTOR+':not(.collapse.collapse-ignore :input)'

	$('.checkout_form').validator(
		#custom: {
		#	zipcode: ($el) ->
		#	 	matchValue = $el.data('phone')
		#	  	# foo
		#	 	if $el.val() != matchValue
		#	    	return 'Hey, that\'s not valid! It\'s gotta be ' + matchValue
		#	  	return
		#}
	)

	$('form.disable_submit_after_submit').submit ->
		# Disable the submit button to prevent repeated clicks:
		$form = $(this)

		if $form.data('bs.validator')
			if !$form.data('bs.validator').hasErrors() && !$form.data('bs.validator').isIncomplete()
				$('input[type=submit], .submit', $form).addClass('disabled').attr('disabled', 'disabled');
		else
			$('input[type=submit], .submit', $form).addClass('disabled').attr('disabled', 'disabled');

		return false;

	$(document).on 'change', '[data-geostateupdate-target]', (event)->
		$select = $(this)
		target = $select.data('geostateupdate-target')
		args = $select.data('geostateupdate-data') || {}
		args['geo_country_id'] = $select.val()

		$.ajax '/checkout/state_input', data: args, success: ( data, status )->
			old_value = $(target).val() unless $(target).is('select')
			$(target).replaceWith( $(data).find( target ) )
			$(target).val(old_value) unless $(target).is('select')

	$('.card-form-group .card-preview').each ->
		$form = $(this).parents('form')
		$form.card({
			container: '.card-preview',
			formSelectors: {
				numberInput: '.card-number',
				expiryInput: '.expiry',
				cvcInput: '.cvc'
			},
			placeholders: {
				name: '',
			}
		})

	$('[data-stripe=number]').payment('formatCardNumber');
	$('[data-stripe=cvc]').payment('formatCardCVC');
	$('[data-stripe=exp]').payment('formatCardExpiry');
	$('.telephone_formatted').each ()->
		$(this).mobilePhoneNumber({ defaultPrefix: '+1' });
