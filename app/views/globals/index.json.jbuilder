json.array!(@globals) do |global|
  json.extract! global, :id, :build_id
  json.url global_url(global, format: :json)
end
