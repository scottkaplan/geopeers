json.array!(@shares) do |share|
  json.extract! share, :id, :expire_time, :device_id, :share_via, :share_to, :share_cred, :share_to, :num_uses, :num_uses_max
  json.url share_url(share, format: :json)
end
