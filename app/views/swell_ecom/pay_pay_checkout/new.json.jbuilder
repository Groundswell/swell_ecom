json.payment_id @payment_id
json.status ( @payment_id.present? ? 'success' : 'errors' )
json.message @message
