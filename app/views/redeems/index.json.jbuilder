json.array!(@redeems) do |redeem|
  json.extract! redeem, :id, :share_id, :device_id
  json.url redeem_url(redeem, format: :json)
end
