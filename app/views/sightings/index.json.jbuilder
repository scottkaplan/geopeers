json.array!(@sightings) do |sighting|
  json.extract! sighting, :id, :device_id, :gps_longitude, :gps_latitude
  json.url sighting_url(sighting, format: :json)
end
