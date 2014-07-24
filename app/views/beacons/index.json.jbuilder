json.array!(@beacons) do |beacon|
  json.extract! beacon, :id, :beacon, :expire_time, :seen_device_id, :seer_device_id
  json.url beacon_url(beacon, format: :json)
end
