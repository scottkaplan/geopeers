json.array!(@devices) do |device|
  json.extract! device, :id, :device_id, :user_agent, :name, :email
  json.url device_url(device, format: :json)
end
